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
    var onCancellation: () -> Void
    
    @State private var archiveDocument: ArchiveFolderDocument?
    @State private var isExporting = false
    @State private var failedFiles: [FailedFileInfo] = []
    
    func body(content: Content) -> some View {
        if #available(macOS 14.0, iOS 17.0, *) {
            content
                .fileExporter(
                    isPresented: $isExporting,
                    document: archiveDocument,
                    contentTypes: [.folder],
                    defaultFilename: "ExcalidrawZ exported at \(Date.now.formatted(date: .abbreviated, time: .shortened))"
                ) { result in
                    handleExportResult(result)
                } onCancellation: {
                    onCancellation()
                }
                .onChange(of: isPresented) { newValue in
                    if newValue {
                        Task {
                            await prepareArchive()
                        }
                    }
                }
        } else {
            content
                .fileExporter(
                    isPresented: $isExporting,
                    document: archiveDocument,
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
    }
    
    private func prepareArchive() async {
        let folderName = "ExcalidrawZ exported at \(Date.now.formatted(date: .abbreviated, time: .shortened))"
        let archiveResult = await archiveAllCloudFilesWithErrorCollection(
            folderName: folderName,
            context: context
        )

        await MainActor.run {
            self.failedFiles = archiveResult.failedFiles
            self.archiveDocument = archiveResult.document
            self.isExporting = true
            self.isPresented = false
        }
    }
    
    /// Internal implementation of archiveAllCloudFiles that collects failed files instead of throwing
    private func archiveAllCloudFilesWithErrorCollection(
        folderName: String,
        context: NSManagedObjectContext
    ) async -> (document: ArchiveFolderDocument, failedFiles: [FailedFileInfo]) {
        var failedFiles: [FailedFileInfo] = []
        let rootWrapper = FileWrapper(directoryWithFileWrappers: [:])
        rootWrapper.preferredFilename = folderName
        
        do {
            let allFiles: [PersistenceController.ExcalidrawGroup: [File]] = try PersistenceController.shared.listAllFiles(context: context)
            
            for groupFiles in allFiles {
                let group = groupFiles.key
                let files = groupFiles.value
                let folderPathComponents = group.ancestors.map { $0.name ?? "Untitled" }
                    + [group.group.name ?? "Untitled"]
                let groupWrapper = archiveFolderWrapper(
                    for: folderPathComponents,
                    in: rootWrapper
                )
                
                for file in files {
                    do {
                        var excalidrawFile = try await ExcalidrawFile(from: file)
                        try await excalidrawFile.syncFiles(context: context)
                        var index = 1
                        var filename = excalidrawFile.name ?? String(localizable: .newFileNamePlaceholder)
                        var retryCount = 0
                        var fileWrapperName = "\(filename).excalidraw"
                        while groupWrapper.fileWrappers?[fileWrapperName] != nil, retryCount < 100 {
                            if filename.hasSuffix(" (\(index))") {
                                filename = filename.replacingOccurrences(of: " (\(index))", with: "")
                                index += 1
                            }
                            filename = "\(filename) (\(index))"
                            fileWrapperName = "\(filename).excalidraw"
                            retryCount += 1
                        }
                        let fileWrapper = FileWrapper(regularFileWithContents: excalidrawFile.content ?? Data())
                        fileWrapper.preferredFilename = fileWrapperName
                        groupWrapper.addFileWrapper(fileWrapper)
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
        
        return (ArchiveFolderDocument(rootWrapper: rootWrapper), failedFiles)
    }
    
    private func handleExportResult(_ result: Result<URL, Error>) {
        switch result {
            case .success(let url):
                // Create ArchiveResult with failed files info
                let archiveResult = ArchiveResult(url: url, failedFiles: failedFiles)
                onComplete(.success(archiveResult))
                
            case .failure(let error):
                onComplete(.failure(error))
        }
        
        // Reset state
        archiveDocument = nil
        failedFiles = []
    }
}

/// Document wrapper for folder export
struct ArchiveFolderDocument: FileDocument, @unchecked Sendable {
    static var readableContentTypes: [UTType] { [.folder] }
    
    let rootWrapper: FileWrapper
    
    init(rootWrapper: FileWrapper) {
        self.rootWrapper = rootWrapper
    }
    
    init(configuration: ReadConfiguration) throws {
        // Not used for export-only document
        throw CocoaError(.fileReadUnsupportedScheme)
    }
    
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        return rootWrapper
    }
}

private func archiveFolderWrapper(
    for pathComponents: [String],
    in root: FileWrapper
) -> FileWrapper {
    var currentWrapper = root
    for component in pathComponents {
        if let existing = currentWrapper.fileWrappers?[component] {
            currentWrapper = existing
            continue
        }
        let newWrapper = FileWrapper(directoryWithFileWrappers: [:])
        newWrapper.preferredFilename = component
        currentWrapper.addFileWrapper(newWrapper)
        currentWrapper = newWrapper
    }
    return currentWrapper
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
        onComplete: @escaping (Result<ArchiveResult, Error>) -> Void,
        onCancellation: @escaping () -> Void
    ) -> some View {
        modifier(
            ArchiveFilesModifier(
                isPresented: isPresented,
                context: context,
                onComplete: onComplete,
                onCancellation: onCancellation
            )
        )
    }
}
