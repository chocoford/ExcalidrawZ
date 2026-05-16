//
//  ExcalidrawFileCover.swift
//  ExcalidrawZ
//
//  Created by Chocoford on 1/1/26.
//

import SwiftUI
import ChocofordUI
import Logging

#if canImport(UIKit)
typealias PlatformImage = UIImage
#elseif canImport(AppKit)
typealias PlatformImage = NSImage
#endif

class FileItemPreviewCache: NSCache<NSString, PlatformImage> {
    static let shared = FileItemPreviewCache()
    
    static func cacheKey(forID id: String, colorScheme: ColorScheme) -> NSString {
        (id + (colorScheme == .light ? "_light" : "_dark")) as NSString
    }
    
    func getPreviewCache(forID id: String, colorScheme: ColorScheme) -> PlatformImage? {
        self.object(forKey: Self.cacheKey(forID: id, colorScheme: colorScheme))
    }
    
    func removePreviewCache(forID id: String, colorScheme: ColorScheme) {
        self.removeObject(forKey: Self.cacheKey(forID: id, colorScheme: colorScheme))
    }

    func removePreviewCache(forID id: String) {
        self.removePreviewCache(forID: id, colorScheme: .light)
        self.removePreviewCache(forID: id, colorScheme: .dark)
    }
}



struct ExcalidrawFileCover: View {
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.scenePhase) var scenePhase
    
    @EnvironmentObject private var fileState: FileState
    
    let logger = Logger(label: "ExcalidrawFileCover")
    
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
                return file.id
        }
    }
    
    let cache = FileItemPreviewCache.shared
    
    var cacheKey: String {
        colorScheme == .light ? fileID + "_light" : fileID + "_dark"
    }
    
    @State private var coverImage: Image? = nil
    @State private var error: Error?
    @State private var generationTask: Task<Void, Never>?
    @State private var generatingCacheKey: String?
    @State private var generationToken = UUID()
    
    var body: some View {
        previewContent
            .apply { view in
                applyListeners(to: view)
            }
            .task(id: cacheKey) {
                loadCover()
            }
            .onReceive(
                NotificationCenter.default.publisher(for: .filePreviewShouldRefresh)
            ) { notification in
                guard let fileID = notification.object as? String,
                      self.fileID == fileID else { return }
                
                print("Refreshing preview for file: \(fileID)")

                cache.removePreviewCache(forID: fileID)
                self.generateCover(forceRefresh: true)
            }
            .onChange(of: scenePhase) { newValue in
                guard fileState.currentActiveFile == nil else { return }
                if newValue == .active {
                    self.loadCover(delay: 0.5)
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
                            cache.removePreviewCache(forID: file.id)
                            self.generateCover(forceRefresh: true)
                        }
#endif
                    }
            case .excalidrawFile:
                view
        }
    }
    
    private func loadCover(delay: TimeInterval = 0) {
        if showCachedCoverIfAvailable() {
            return
        }

        guard delay > 0 else {
            generateCover()
            return
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            if !showCachedCoverIfAvailable() {
                generateCover()
            }
        }
    }

    @discardableResult
    private func showCachedCoverIfAvailable() -> Bool {
        guard let image = cache.getPreviewCache(forID: fileID, colorScheme: colorScheme) else {
            return false
        }

        generationTask?.cancel()
        generationToken = UUID()
        generatingCacheKey = nil
        coverImage = Image(platformImage: image)
        error = nil
        return true
    }

    private func generateCover(forceRefresh: Bool = false) {
        let fileID = self.fileID
        let colorScheme = self.colorScheme
        let cacheKey = self.cacheKey

        if !forceRefresh, showCachedCoverIfAvailable() {
            return
        }

        guard forceRefresh || generatingCacheKey != cacheKey else {
            return
        }

        generationTask?.cancel()
        generatingCacheKey = cacheKey
        let generationToken = UUID()
        self.generationToken = generationToken
        generationTask = Task {
            do {
                // Load ExcalidrawFile based on source
                let excalidrawFile: ExcalidrawFile
                
                switch source {
                    case .activeFile(let activeFile):
                        // Load from ActiveFile
                        switch activeFile {
                            case .file(let file):
                                let content = try await file.loadContent()
                                excalidrawFile = try ExcalidrawFile(data: content, id: activeFile.id)
                            case .localFile(let url):
                                try await FileCoordinator.shared.downloadFile(url: url)
                                excalidrawFile = try ExcalidrawFile(contentsOf: url)
                            case .temporaryFile(let url):
                                excalidrawFile = try ExcalidrawFile(contentsOf: url)
                            case .collaborationFile(let collaborationFile):
                                let content = try await collaborationFile.loadContent()
                                excalidrawFile = try ExcalidrawFile(data: content, id: collaborationFile.id?.uuidString)
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
                    guard !Task.isCancelled else {
                        await finishGeneration(cacheKey: cacheKey, generationToken: generationToken)
                        return
                    }
                    Task.detached {
                        guard let cgThumb = image.downsampledCGImage(maxPixelSize: 720) else {
                            await MainActor.run {
                                self.finishGeneration(cacheKey: cacheKey, generationToken: generationToken)
                            }
                            return
                        }
#if canImport(UIKit)
                        let thumbnail = UIImage(cgImage: cgThumb)
#elseif canImport(AppKit)
                        let thumbnail = NSImage(cgImage: cgThumb, size: .zero)
#endif
                        await MainActor.run {
                            guard self.generationToken == generationToken,
                                  self.fileID == fileID,
                                  self.colorScheme == colorScheme else { return }
                            cache.setObject(thumbnail, forKey: cacheKey as NSString)
                            let image = Image(platformImage: thumbnail)
                            self.coverImage = image
                            self.error = nil
                            self.finishGeneration(cacheKey: cacheKey, generationToken: generationToken)
                        }
                    }
                } else {
                    await finishGeneration(cacheKey: cacheKey, generationToken: generationToken)
                }
            } catch {
                guard !Task.isCancelled else {
                    await finishGeneration(cacheKey: cacheKey, generationToken: generationToken)
                    return
                }
                self.logger.error("Failed to load excalidraw file for preview: \(error)")
                await MainActor.run {
                    guard self.generationToken == generationToken else { return }
                    self.error = error
                    self.finishGeneration(cacheKey: cacheKey, generationToken: generationToken)
                }
            }
        }
    }

    @MainActor
    private func finishGeneration(cacheKey: String, generationToken: UUID) {
        guard self.generationToken == generationToken,
              generatingCacheKey == cacheKey else { return }
        generatingCacheKey = nil
        generationTask = nil
    }
}


#if canImport(AppKit)
extension NSImage {
    func downsampledCGImage(maxPixelSize: CGFloat) -> CGImage? {
        var rect = CGRect(origin: .zero, size: size)
        guard let cgImage = self.cgImage(forProposedRect: &rect, context: nil, hints: nil) else {
            return nil
        }

        let width = CGFloat(cgImage.width)
        let height = CGFloat(cgImage.height)
        let scale = maxPixelSize / max(width, height)
        let targetSize = CGSize(width: max(1, width * scale), height: max(1, height * scale))

        guard let ctx = CGContext(
            data: nil,
            width: Int(targetSize.width),
            height: Int(targetSize.height),
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        ctx.interpolationQuality = .low
        ctx.draw(cgImage, in: CGRect(origin: .zero, size: targetSize))
        return ctx.makeImage()
    }
}
#endif

#if canImport(UIKit)
extension UIImage {
    func downsampledCGImage(maxPixelSize: CGFloat) -> CGImage? {
        let cgImage: CGImage
        if let image = self.cgImage {
            cgImage = image
        } else if let ciImage = self.ciImage {
            let context = CIContext(options: nil)
            guard let image = context.createCGImage(ciImage, from: ciImage.extent) else {
                return nil
            }
            cgImage = image
        } else {
            return nil
        }

        let width = CGFloat(cgImage.width)
        let height = CGFloat(cgImage.height)
        let scale = maxPixelSize / max(width, height)
        let targetSize = CGSize(width: max(1, width * scale), height: max(1, height * scale))

        guard let ctx = CGContext(
            data: nil,
            width: Int(targetSize.width),
            height: Int(targetSize.height),
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        ctx.interpolationQuality = .low
        ctx.draw(cgImage, in: CGRect(origin: .zero, size: targetSize))
        return ctx.makeImage()
    }
}
#endif
