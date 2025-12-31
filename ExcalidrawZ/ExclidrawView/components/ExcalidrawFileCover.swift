//
//  ExcalidrawFileCover.swift
//  ExcalidrawZ
//
//  Created by Chocoford on 1/1/26.
//

import SwiftUI
import ChocofordUI

#if canImport(UIKit)
typealias PlatformImage = UIImage
#elseif canImport(AppKit)
typealias PlatformImage = NSImage
#endif

class FileItemPreviewCache: NSCache<NSString, PlatformImage> {
    static let shared = FileItemPreviewCache()
    
    static func cacheKey(forID id: String, colorScheme: ColorScheme) -> NSString {
        id + (colorScheme == .light ? "_light" : "_dark") as NSString
    }
    
    func getPreviewCache(forID id: String, colorScheme: ColorScheme) -> PlatformImage? {
        self.object(forKey: Self.cacheKey(forID: id, colorScheme: colorScheme))
    }
    
    func removePreviewCache(forID id: String, colorScheme: ColorScheme) {
        self.removeObject(forKey: Self.cacheKey(forID: id, colorScheme: colorScheme))
    }
}



struct ExcalidrawFileCover: View {
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.scenePhase) var scenePhase
    
    @EnvironmentObject private var fileState: FileState
    
    // Support two initialization modes
    private enum Source {
        case activeFile(FileState.ActiveFile)
        case excalidrawFile(ExcalidrawFile)
    }
    
    private let source: Source
    
    init(file: FileState.ActiveFile) {
        self.source = .activeFile(file)
    }
    
    init(excalidrawFile: ExcalidrawFile) {
        self.source = .excalidrawFile(excalidrawFile)
    }
    
    var fileID: String {
        switch source {
            case .activeFile(let file):
                return file.id
            case .excalidrawFile(let file):
                return file.id.uuidString
        }
    }
    
    let cache = FileItemPreviewCache.shared
    
    var cacheKey: String {
        colorScheme == .light ? fileID + "_light" : fileID + "_dark"
    }
    
    @State private var coverImage: Image? = nil
    @State private var error: Error?
    
    var body: some View {
        previewContent
            .apply { view in
                applyListeners(to: view)
            }
            .onReceive(
                NotificationCenter.default.publisher(for: .filePreviewShouldRefresh)
            ) { notification in
                guard let fileID = notification.object as? String,
                      self.fileID == fileID else { return }
                
                print("Refreshing preview for file: \(fileID)")
                
                self.generateCover()
            }
            .onChange(of: fileID) { _ in
                self.generateCover()
            }
            .watchImmediately(of: colorScheme) { _ in
                guard scenePhase == .active else { return }
                if let image = cache.getPreviewCache(forID: fileID, colorScheme: colorScheme) {
                    Task.detached {
                        let image = Image(platformImage: image)
                        await MainActor.run {
                            self.coverImage = image
                        }
                    }
                } else {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        self.generateCover()
                    }
                }
            }
            .onChange(of: scenePhase) { newValue in
                guard fileState.currentActiveFile == nil else { return }
                if newValue == .active {
                    if let image = cache.getPreviewCache(forID: fileID, colorScheme: colorScheme) {
                        Task.detached {
                            let image = Image(platformImage: image)
                            await MainActor.run {
                                self.coverImage = image
                            }
                        }
                    } else {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            self.generateCover()
                        }
                    }
                }
            }
    }
    
    @ViewBuilder
    private var previewContent: some View {
        ZStack {
            if let coverImage {
                coverImage
                    .resizable()
            } else if error != nil {
                Image(systemSymbol: .exclamationmarkTriangle)
                    .foregroundStyle(.secondary)
            } else {
                ProgressView()
                    .controlSize(.small)
            }
        }
    }
    
    @ViewBuilder
    private func applyListeners<V: View>(to view: V) -> some View {
        switch source {
            case .activeFile(let file):
                // Apply all listeners for ActiveFile
                view
                    .observeFileStatus(for: file) { status in
#if os(macOS)
                        if status.iCloudStatus == .outdated {
                            self.generateCover()
                        }
#endif
                    }
            case .excalidrawFile:
                view
        }
    }
    
    private func generateCover() {
        Task {
            do {
                // Load ExcalidrawFile based on source
                let excalidrawFile: ExcalidrawFile
                
                switch source {
                    case .activeFile(let file):
                        // Load from ActiveFile
                        switch file {
                            case .file(let file):
                                let content = try await file.loadContent()
                                excalidrawFile = try ExcalidrawFile(data: content, id: file.id)
                            case .localFile(let url):
                                try await FileCoordinator.shared.downloadFile(url: url)
                                excalidrawFile = try ExcalidrawFile(contentsOf: url)
                            case .temporaryFile(let url):
                                excalidrawFile = try ExcalidrawFile(contentsOf: url)
                            case .collaborationFile(let collaborationFile):
                                let content = try await collaborationFile.loadContent()
                                excalidrawFile = try ExcalidrawFile(data: content, id: collaborationFile.id)
                        }
                        
                    case .excalidrawFile(let file):
                        // Use provided ExcalidrawFile directly
                        excalidrawFile = file
                }
                
                // Wait for coordinator to be ready
                while fileState.excalidrawWebCoordinator?.isLoading == true {
                    try? await Task.sleep(nanoseconds: UInt64(1e+9 * 1))
                }
                
                // Generate preview image
                if let image = try? await fileState.excalidrawWebCoordinator?.exportElementsToPNG(
                    elements: excalidrawFile.elements,
                    files: excalidrawFile.files.isEmpty ? nil : excalidrawFile.files,
                    colorScheme: colorScheme
                ) {
                    Task.detached {
                        await MainActor.run {
                            cache.setObject(image, forKey: cacheKey as NSString)
                        }
                        let image = Image(platformImage: image)
                        await MainActor.run {
                            self.coverImage = image
                            self.error = nil
                        }
                    }
                }
            } catch {
                print("Failed to load excalidraw file for preview:", error)
                self.error = error
            }
        }
    }
}
