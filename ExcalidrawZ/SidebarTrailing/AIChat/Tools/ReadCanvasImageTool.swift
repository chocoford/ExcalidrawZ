//
//  ReadCanvasImageTool.swift
//  ExcalidrawZ
//

import Foundation
import ImageIO
import UniformTypeIdentifiers
import LLMCore

/// Take a PNG snapshot of the current Excalidraw canvas and return it as a
/// multimodal tool result (text caption + image). The image goes to the
/// vision model natively — pair with `read_file` (structural element data)
/// when you need to *see* the canvas: layout, hand-drawn detail, colors, or
/// any visual quality the structural read can't capture.
struct ReadCanvasImageTool: Tool {
    struct ReadCanvasImageContext: ToolContext {
        var canvasTarget: ExcalidrawCoordinatorRegistry.CanvasTarget
        var currentModelSupportsImageInput: Bool?
    }

    var name: String { "read_canvas_image" }

    var displayName: String { String(localizable: .aiChatToolReadCanvasImageName) }

    var description: String {
        """
        Take a PNG snapshot of the current Excalidraw canvas and return it as
        an image. Use this when you need to visually inspect the canvas —
        layout, spatial relationships, hand-drawn details, colors — anything
        the structural `read_file` tool can't capture. No arguments required;
        always returns the full canvas at the user's current viewport scale.
        """
    }

    var inputSchema: ToolInputSchema {
        .parameters(ToolParameters(properties: [:], required: []))
    }

    func execute(_ input: String, context: (any ChatInvocationContext)?) async throws -> ToolResult {
        try AIChatToolExecutionGate.ensureAIEnabled()

        guard let context else {
            throw ToolError.executionFailed("Missing ReadCanvasImageContext")
        }
        let canvasContext = try context.resolve(ReadCanvasImageContext.self)
        guard canvasContext.currentModelSupportsImageInput ?? true else {
            return .text("The current model cannot read image tool results. Use read_file for structural canvas data instead.")
        }

        let coordinator = await MainActor.run {
            ExcalidrawCoordinatorRegistry.shared.coordinator(for: canvasContext.canvasTarget)
        }
        guard let coordinator else {
            throw ToolError.executionFailed("Missing active Excalidraw coordinator")
        }

        let elementCount = await MainActor.run {
            coordinator.parent?.file?.elements.filter { !$0.isDeleted }.count ?? 0
        }

        if elementCount == 0 {
            return .text("Canvas is empty — nothing to capture.")
        }

        let rawPNG: Data
        do {
            guard let data = try await coordinator.exportPNGData() else {
                throw ToolError.executionFailed("No active file to export.")
            }
            rawPNG = data
        } catch let error as ToolError {
            throw error
        } catch {
            throw ToolError.executionFailed("Failed to export canvas: \(error.localizedDescription)")
        }

        let pngData = Self.boundedPNG(rawPNG)
        let caption = "Canvas snapshot (\(elementCount) element\(elementCount == 1 ? "" : "s"))."
        return .parts([
            .text(caption),
            .image(.data(pngData, mediaType: "image/png"))
        ])
    }

    /// Anthropic's documented "best efficiency" longest edge — anything bigger
    /// gets server-side resized anyway, but we still pay the upload cost. Cap
    /// locally so the wire payload stays compact and predictable.
    private static let maxImageEdge: CGFloat = 1568

    /// Downsample the PNG to fit within `maxImageEdge` on the longest side.
    /// If the original is already small enough, return it unchanged.
    /// On any decode/encode failure, fall back to the original — better to ship
    /// a too-large image than to fail the tool call.
    private static func boundedPNG(_ data: Data) -> Data {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            return data
        }
        // Skip work if already within bounds.
        if let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
           let width = props[kCGImagePropertyPixelWidth] as? CGFloat,
           let height = props[kCGImagePropertyPixelHeight] as? CGFloat,
           max(width, height) <= maxImageEdge {
            return data
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxImageEdge
        ]
        guard let downsampled = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return data
        }
        let buffer = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(
            buffer,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else {
            return data
        }
        CGImageDestinationAddImage(dest, downsampled, nil)
        guard CGImageDestinationFinalize(dest) else {
            return data
        }
        return buffer as Data
    }
}
