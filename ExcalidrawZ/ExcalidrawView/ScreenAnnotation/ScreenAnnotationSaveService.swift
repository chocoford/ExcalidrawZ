#if os(macOS)
import AppKit
import UniformTypeIdentifiers

@MainActor
enum ScreenAnnotationSaveService {
    enum SaveError: LocalizedError {
        case imageUnavailable
        case imageEncodingFailed(ScreenAnnotationSaveFormat)
        case annotationDocumentUnavailable

        var errorDescription: String? {
            switch self {
                case .imageUnavailable:
                    "The screen annotation image is unavailable."
                case .imageEncodingFailed(let format):
                    "The screen annotation could not be encoded as \(format.title)."
                case .annotationDocumentUnavailable:
                    "The Excalidraw annotation document could not be created."
            }
        }
    }

    static func croppedImage(
        _ image: NSImage,
        to region: CGRect?
    ) throws -> NSImage {
        guard let region else { return image }

        let imageBounds = CGRect(origin: .zero, size: image.size)
        let cropRect = region.intersection(imageBounds)
        guard !cropRect.isNull, !cropRect.isEmpty else {
            throw SaveError.imageUnavailable
        }

        guard let cgImage = image.cgImage(
            forProposedRect: nil,
            context: nil,
            hints: nil
        ) else {
            throw SaveError.imageUnavailable
        }
        let scaleX = CGFloat(cgImage.width) / image.size.width
        let scaleY = CGFloat(cgImage.height) / image.size.height
        let pixelRect = CGRect(
            x: cropRect.minX * scaleX,
            y: cropRect.minY * scaleY,
            width: cropRect.width * scaleX,
            height: cropRect.height * scaleY
        ).integral
        guard let croppedCGImage = cgImage.cropping(to: pixelRect) else {
            throw SaveError.imageUnavailable
        }

        let representation = NSBitmapImageRep(cgImage: croppedCGImage)
        representation.size = cropRect.size
        let output = NSImage(size: cropRect.size)
        output.addRepresentation(representation)
        return output
    }

    static func imageData(
        from image: NSImage,
        format: ScreenAnnotationSaveFormat,
        jpegCompressionFactor: Double = 0.92
    ) throws -> Data {
        guard let cgImage = image.cgImage(
            forProposedRect: nil,
            context: nil,
            hints: nil
        ) else {
            throw SaveError.imageEncodingFailed(format)
        }
        let representation = NSBitmapImageRep(cgImage: cgImage)
        representation.size = image.size
        guard let data = representation.representation(
            using: format.bitmapFileType,
            properties: format.bitmapProperties(
                jpegCompressionFactor: jpegCompressionFactor
            )
        ) else {
            throw SaveError.imageEncodingFailed(format)
        }
        return data
    }

    static func optimizedImage(
        _ image: NSImage,
        quality: ScreenAnnotationImageQuality
    ) throws -> NSImage {
        guard quality != .original else {
            return image
        }
        guard let sourceImage = image.cgImage(
            forProposedRect: nil,
            context: nil,
            hints: nil
        ) else {
            throw SaveError.imageUnavailable
        }

        let sourceSize = CGSize(
            width: CGFloat(sourceImage.width),
            height: CGFloat(sourceImage.height)
        )
        var scale: CGFloat = 1

        if let maximumPixelsPerPoint = quality.maximumPixelsPerPoint {
            let logicalSize = image.size
            let sourcePixelsPerPoint = max(
                sourceSize.width / max(logicalSize.width, 1),
                sourceSize.height / max(logicalSize.height, 1)
            )
            scale = min(
                scale,
                maximumPixelsPerPoint / max(sourcePixelsPerPoint, 1)
            )
        }

        if let maximumLongEdge = quality.maximumLongEdge {
            scale = min(
                scale,
                maximumLongEdge / max(sourceSize.width, sourceSize.height)
            )
        }

        guard scale < 0.999 else {
            return image
        }

        let targetWidth = max(
            1,
            Int((sourceSize.width * scale).rounded())
        )
        let targetHeight = max(
            1,
            Int((sourceSize.height * scale).rounded())
        )
        guard let context = CGContext(
            data: nil,
            width: targetWidth,
            height: targetHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: sourceImage.colorSpace ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw SaveError.imageUnavailable
        }

        context.interpolationQuality = .high
        context.draw(
            sourceImage,
            in: CGRect(
                x: 0,
                y: 0,
                width: targetWidth,
                height: targetHeight
            )
        )
        guard let resizedImage = context.makeImage() else {
            throw SaveError.imageUnavailable
        }

        let representation = NSBitmapImageRep(cgImage: resizedImage)
        representation.size = image.size
        let output = NSImage(size: image.size)
        output.addRepresentation(representation)
        return output
    }

    static func copyToClipboard(
        _ data: Data,
        format: ScreenAnnotationSaveFormat
    ) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setData(
            data,
            forType: NSPasteboard.PasteboardType(format.contentType.identifier)
        )
    }

    static func chooseCustomLocation(
        format: ScreenAnnotationSaveFormat
    ) -> URL? {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [format.contentType]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = defaultFilename(format: format)

        NSApp.activate(ignoringOtherApps: true)
        panel.level = .modalPanel
        panel.orderFrontRegardless()
        panel.makeKey()
        return panel.runModal() == .OK ? panel.url : nil
    }

    static func save(_ data: Data, to url: URL) throws {
        try data.write(to: url, options: .atomic)
    }

    private static func defaultFilename(
        format: ScreenAnnotationSaveFormat
    ) -> String {
        "Screen Annotation \(timestampFormatter.string(from: Date())).\(format.fileExtension)"
    }

    private static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
        return formatter
    }()
}
#endif
