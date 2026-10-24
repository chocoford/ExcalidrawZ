//
//  LibraryItemPreviewCoordinator.swift
//  ExcalidrawZ
//
//  Created by Codex on 2026/6/26.
//

import CoreData
import Logging
import SwiftUI

private let libraryItemPreviewLogger = Logger(label: "LibraryItemPreviewCoordinator")

extension Notification.Name {
    static let libraryItemPreviewDidUpdate = Notification.Name("LibraryItemPreviewDidUpdate")
}

enum LibraryItemPreviewSource {
    case managed(objectID: NSManagedObjectID, itemID: String)
    case inline(itemID: String, elements: [ExcalidrawElement])

    var id: String {
        switch self {
            case .managed(let objectID, let itemID):
                return "libraryItem:\(itemID.isEmpty ? objectID.uriRepresentation().absoluteString : itemID)"
            case .inline(let itemID, _):
                return "libraryItem:\(itemID)"
        }
    }
}

struct LibraryItemPreviewUpdate {
    let sourceID: String
    let colorScheme: ColorScheme
    let image: PlatformImage
}

final class LibraryItemPreviewCache: NSCache<NSString, PlatformImage> {
    static let shared = LibraryItemPreviewCache()

    static func cacheKey(forID id: String, colorScheme: ColorScheme) -> NSString {
        "\(id)_\(colorScheme == .dark ? "dark" : "light")" as NSString
    }

    private override init() {
        super.init()
        countLimit = 300
    }
}

@MainActor
final class LibraryItemPreviewCoordinator {
    static let shared = LibraryItemPreviewCoordinator()

    private struct Job {
        let source: LibraryItemPreviewSource
        let colorScheme: ColorScheme
        let retryCount: Int

        var cacheKey: String {
            LibraryItemPreviewCache.cacheKey(forID: source.id, colorScheme: colorScheme) as String
        }
    }

    private enum GenerationResult: Equatable {
        case completed
        case retry
    }

    private let cache = LibraryItemPreviewCache.shared
    private let thumbnailMaxPixelSize: CGFloat = 180
    private let maximumRetryCount = 40

    private weak var fileState: FileState?
    private weak var fallbackCoordinator: ExcalidrawCanvasView.Coordinator?
    private var queue: [Job] = []
    private var queuedKeys: Set<String> = []
    private var inFlightKeys: Set<String> = []
    private var processingTask: Task<Void, Never>?

    private init() {}

    func register(fileState: FileState) {
        self.fileState = fileState
    }

    func request(
        source: LibraryItemPreviewSource,
        colorScheme: ColorScheme,
        coordinator: ExcalidrawCanvasView.Coordinator? = nil
    ) {
        if let coordinator {
            fallbackCoordinator = coordinator
        }

        let cacheKey = LibraryItemPreviewCache.cacheKey(
            forID: source.id,
            colorScheme: colorScheme
        ) as String

        if cache.object(forKey: cacheKey as NSString) != nil {
            return
        }

        guard !queuedKeys.contains(cacheKey),
              !inFlightKeys.contains(cacheKey) else {
            return
        }

        queuedKeys.insert(cacheKey)
        queue.append(Job(
            source: source,
            colorScheme: colorScheme,
            retryCount: 0
        ))
        startProcessingIfNeeded()
    }

    func cancelRequest(
        source: LibraryItemPreviewSource,
        colorScheme: ColorScheme
    ) {
        let cacheKey = LibraryItemPreviewCache.cacheKey(
            forID: source.id,
            colorScheme: colorScheme
        ) as String
        queue.removeAll { $0.cacheKey == cacheKey }
        queuedKeys.remove(cacheKey)
    }

    private func startProcessingIfNeeded() {
        guard processingTask == nil else { return }
        processingTask = Task { @MainActor in
            await processQueue()
        }
    }

    private func processQueue() async {
        defer {
            processingTask = nil
            if !queue.isEmpty {
                startProcessingIfNeeded()
            }
        }

        while !Task.isCancelled, !queue.isEmpty {
            let job = queue.removeFirst()
            queuedKeys.remove(job.cacheKey)

            if cache.object(forKey: job.cacheKey as NSString) != nil {
                continue
            }

            inFlightKeys.insert(job.cacheKey)
            let result = await generate(job)
            inFlightKeys.remove(job.cacheKey)

            if result == .retry {
                try? await Task.sleep(nanoseconds: 750_000_000)
                guard !Task.isCancelled else { return }
                requeue(job)
            }
        }
    }

    private func requeue(_ job: Job) {
        guard job.retryCount < maximumRetryCount else {
            libraryItemPreviewLogger.warning("Dropped library item preview after retries for \(job.source.id)")
            return
        }

        guard cache.object(forKey: job.cacheKey as NSString) == nil,
              !queuedKeys.contains(job.cacheKey),
              !inFlightKeys.contains(job.cacheKey) else {
            return
        }

        queuedKeys.insert(job.cacheKey)
        queue.append(Job(
            source: job.source,
            colorScheme: job.colorScheme,
            retryCount: job.retryCount + 1
        ))
    }

    private func generate(_ job: Job) async -> GenerationResult {
        do {
            guard let coordinator = await waitForPreviewExporter() else {
                libraryItemPreviewLogger.debug("Library item preview exporter unavailable for \(job.source.id), retry=\(job.retryCount)")
                return .retry
            }

            let elements = try await loadElements(for: job.source)
            guard !Task.isCancelled, !elements.isEmpty else { return .completed }

            let image = try await coordinator.exportElementsPreviewToPNG(
                elements: elements,
                withBackground: false,
                colorScheme: job.colorScheme
            )
            guard !Task.isCancelled else { return .completed }

            let previewImage = makeThumbnail(from: image) ?? image
            cache.setObject(previewImage, forKey: job.cacheKey as NSString)
            // NSCache may immediately discard the entry; deliver the image itself.
            NotificationCenter.default.post(
                name: .libraryItemPreviewDidUpdate,
                object: LibraryItemPreviewUpdate(
                    sourceID: job.source.id,
                    colorScheme: job.colorScheme,
                    image: previewImage
                )
            )
            return .completed
        } catch ExcalidrawPreviewExportError.notReady(let summary) {
            libraryItemPreviewLogger.debug("Library item preview exporter not ready for \(job.source.id): \(summary)")
            return .retry
        } catch ExcalidrawPreviewExportError.timedOut(let label, let timeout) {
            libraryItemPreviewLogger.debug("Library item preview export timed out for \(job.source.id): \(label), timeout=\(timeout)s")
            return .retry
        } catch {
            libraryItemPreviewLogger.warning("Failed to render library item preview: \(error)")
            return .completed
        }
    }

    private func waitForPreviewExporter() async -> ExcalidrawCanvasView.Coordinator? {
        var lastReadinessSummary = "coordinator=nil"
        for _ in 0..<20 {
            guard !Task.isCancelled else { return nil }

            if let coordinator = fileState?.excalidrawWebCoordinator ?? fallbackCoordinator {
                lastReadinessSummary = coordinator.previewExportReadinessSummary
                if coordinator.isReadyForPreviewExport {
                    return coordinator
                }
            } else {
                lastReadinessSummary = "coordinator=nil"
            }

            try? await Task.sleep(nanoseconds: 250_000_000)
        }

        libraryItemPreviewLogger.debug("Library item preview exporter unavailable: \(lastReadinessSummary)")
        return nil
    }

    private func loadElements(
        for source: LibraryItemPreviewSource
    ) async throws -> [ExcalidrawElement] {
        switch source {
            case .inline(_, let elements):
                return elements

            case .managed(let objectID, _):
                let context = PersistenceController.shared.container.newBackgroundContext()
                return try await context.perform {
                    guard let item = try context.existingObject(with: objectID) as? LibraryItem,
                          let data = item.elements else {
                        return []
                    }
                    return try JSONDecoder().decode([ExcalidrawElement].self, from: data)
                }
        }
    }

    private func makeThumbnail(from image: PlatformImage) -> PlatformImage? {
        guard let cgThumb = image.downsampledCGImage(maxPixelSize: thumbnailMaxPixelSize) else {
            return nil
        }
#if canImport(UIKit)
        return UIImage(cgImage: cgThumb)
#elseif canImport(AppKit)
        return NSImage(
            cgImage: cgThumb,
            size: CGSize(
                width: CGFloat(cgThumb.width),
                height: CGFloat(cgThumb.height)
            )
        )
#endif
    }
}
