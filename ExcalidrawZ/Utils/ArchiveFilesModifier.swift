//
//  ArchiveFilesModifier.swift
//  ExcalidrawZ
//
//  Created by Claude on 2025/11/29.
//

import SwiftUI
import CoreData
import UniformTypeIdentifiers

/// Information about a file that failed to archive
struct FailedFileInfo: Identifiable {
    let id = UUID()
    let fileName: String
    let error: String
}

/// Result of archiving operation
struct ArchiveResult {
    let url: URL
    let failedFiles: [FailedFileInfo]
}

/// ViewModifier for archiving all files with fileExporter
/// This is a SwiftUI-native implementation of archiveAllFiles() from Utils.swift
/// that supports both macOS and iOS using fileExporter
struct ArchiveFilesModifier: ViewModifier {
    @Binding var isPresented: Bool
    let context: NSManagedObjectContext
    let onComplete: (Result<ArchiveResult, Error>) -> Void
    
    @State private var archiveURL: URL?
    @State private var isExporting = false
    @State private var failedFiles: [FailedFileInfo] = []
    
    func body(content: Content) -> some View {
        content
            .fileExporter(
                isPresented: $isExporting,
                document: archiveURL.map { ArchiveFolderDocument(url: $0) },
                contentType: .folder,
                defaultFilename: "ExcalidrawZ exported at \(Date.now.formatted(date: .abbreviated, time: .shortened))"
            ) { result in
                handleExportResult(result)
            }
            .onChange(of: isPresented) { newValue in
                if newValue {
                    Task {
                        await prepareArchive()
                    }
                }
            }
    }
    
    private func prepareArchive() async {
        do {
            let fileManager = FileManager.default
            
            // Create temporary directory for archive
            // This matches the original implementation: create a folder with timestamp
            let tempDir = fileManager.temporaryDirectory
            let folderName = "ExcalidrawZ exported at \(Date.now.formatted(date: .abbreviated, time: .shortened))"
            let tempArchiveURL = tempDir.appendingPathComponent(folderName, conformingTo: .directory)
            
            // Create the directory (like in original archiveAllFiles)
            try fileManager.createDirectory(at: tempArchiveURL, withIntermediateDirectories: false)
            
            // Archive all files to temp directory (using internal implementation with error collection)
            let failed = await archiveAllCloudFilesWithErrorCollection(to: tempArchiveURL, context: context)
            
            // Store failed files and URL, then present file exporter
            await MainActor.run {
                self.failedFiles = failed
                self.archiveURL = tempArchiveURL
                self.isExporting = true
                self.isPresented = false
            }
        } catch {
            await MainActor.run {
                self.isPresented = false
                onComplete(.failure(error))
            }
        }
    }
    
    /// Internal implementation of archiveAllCloudFiles that collects failed files instead of throwing
    private func archiveAllCloudFilesWithErrorCollection(to url: URL, context: NSManagedObjectContext) async -> [FailedFileInfo] {
        var failedFiles: [FailedFileInfo] = []
        let filemanager = FileManager.default
        
        do {
            let allFiles: [PersistenceController.ExcalidrawGroup: [File]] = try PersistenceController.shared.listAllFiles(context: context)
            
            for groupFiles in allFiles {
                let group = groupFiles.key
                let files = groupFiles.value
                var groupURL = url
                for ancestor in group.ancestors {
                    groupURL = groupURL.appendingPathComponent(ancestor.name ?? "Untitled", conformingTo: .directory)
                }
                groupURL = groupURL.appendingPathComponent(group.group.name ?? "Untitled", conformingTo: .directory)
                if !filemanager.fileExists(at: groupURL) {
                    try filemanager.createDirectory(at: groupURL, withIntermediateDirectories: true)
                }
                
                for file in files {
                    do {
                        var excalidrawFile = try await ExcalidrawFile(from: file)
                        try await excalidrawFile.syncFiles(context: context)
                        var index = 1
                        var filename = excalidrawFile.name ?? String(localizable: .newFileNamePlaceholder)
                        var fileURL: URL = groupURL.appendingPathComponent(filename, conformingTo: .fileURL).appendingPathExtension("excalidraw")
                        var retryCount = 0
                        while filemanager.fileExists(at: fileURL), retryCount < 100 {
                            if filename.hasSuffix(" (\(index))") {
                                filename = filename.replacingOccurrences(of: " (\(index))", with: "")
                                index += 1
                            }
                            filename = "\(filename) (\(index))"
                            fileURL = fileURL
                                .deletingLastPathComponent()
                                .appendingPathComponent(filename, conformingTo: .excalidrawFile)
                            retryCount += 1
                        }
                        let filePath: String = fileURL.filePath
                        if !filemanager.createFile(atPath: filePath, contents: excalidrawFile.content) {
                            print("export file \(filePath) failed")
                            failedFiles.append(FailedFileInfo(
                                fileName: filename,
                                error: "Failed to create file"
                            ))
                        } else {
                            print("Export file to url<\(filePath)> done")
                        }
                    } catch {
                        // Record failed file instead of throwing
                        let fileName = file.name ?? "Untitled"
                        failedFiles.append(FailedFileInfo(
                            fileName: fileName,
                            error: error.localizedDescription
                        ))
                        print("Failed to archive file '\(fileName)': \(error.localizedDescription)")
                    }
                }
            }
        } catch {
            // If we fail to list files, record a general error
            failedFiles.append(FailedFileInfo(
                fileName: "Archive",
                error: "Failed to list files: \(error.localizedDescription)"
            ))
        }
        
        return failedFiles
    }
    
    private func handleExportResult(_ result: Result<URL, Error>) {
        switch result {
            case .success(let url):
                // Clean up temporary directory after successful export
                if let archiveURL = archiveURL {
                    try? FileManager.default.removeItem(at: archiveURL)
                }
                // Create ArchiveResult with failed files info
                let archiveResult = ArchiveResult(url: url, failedFiles: failedFiles)
                onComplete(.success(archiveResult))
                
            case .failure(let error):
                // Clean up temporary directory on failure
                if let archiveURL = archiveURL {
                    try? FileManager.default.removeItem(at: archiveURL)
                }
                onComplete(.failure(error))
        }
        
        // Reset state
        archiveURL = nil
        failedFiles = []
    }
}

/// Document wrapper for folder export
struct ArchiveFolderDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.folder] }
    
    let url: URL
    
    init(url: URL) {
        self.url = url
    }
    
    init(configuration: ReadConfiguration) throws {
        // Not used for export-only document
        throw CocoaError(.fileReadUnsupportedScheme)
    }
    
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        return try FileWrapper(url: url, options: .immediate)
    }
}

extension View {
    /// Present a file exporter to archive all files
    /// - Parameters:
    ///   - isPresented: Binding to control presentation
    ///   - context: NSManagedObjectContext for fetching files
    ///   - onComplete: Completion handler with result (includes failed files info)
    func archiveFilesExporter(
        isPresented: Binding<Bool>,
        context: NSManagedObjectContext,
        onComplete: @escaping (Result<ArchiveResult, Error>) -> Void
    ) -> some View {
        modifier(
            ArchiveFilesModifier(
                isPresented: isPresented,
                context: context,
                onComplete: onComplete
            )
        )
    }
}
