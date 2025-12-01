//
//  ArchiveFilesModifier.swift
//  ExcalidrawZ
//
//  Created by Claude on 2025/11/29.
//

import SwiftUI
import CoreData
import UniformTypeIdentifiers

/// ViewModifier for archiving all files with fileExporter
/// This is a SwiftUI-native implementation of archiveAllFiles() from Utils.swift
/// that supports both macOS and iOS using fileExporter
struct ArchiveFilesModifier: ViewModifier {
    @Binding var isPresented: Bool
    let context: NSManagedObjectContext
    let onComplete: (Result<URL, Error>) -> Void

    @State private var archiveURL: URL?
    @State private var isExporting = false

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

            // Archive all files to temp directory (original archiveAllCloudFiles call)
            try await archiveAllCloudFiles(to: tempArchiveURL, context: context)

            // Store URL and present file exporter
            await MainActor.run {
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

    private func handleExportResult(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            // Clean up temporary directory after successful export
            if let archiveURL = archiveURL {
                try? FileManager.default.removeItem(at: archiveURL)
            }
            onComplete(.success(url))

        case .failure(let error):
            // Clean up temporary directory on failure
            if let archiveURL = archiveURL {
                try? FileManager.default.removeItem(at: archiveURL)
            }
            onComplete(.failure(error))
        }

        // Reset state
        archiveURL = nil
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
    ///   - onComplete: Completion handler with result
    func archiveFilesExporter(
        isPresented: Binding<Bool>,
        context: NSManagedObjectContext,
        onComplete: @escaping (Result<URL, Error>) -> Void
    ) -> some View {
        modifier(ArchiveFilesModifier(
            isPresented: isPresented,
            context: context,
            onComplete: onComplete
        ))
    }
}
