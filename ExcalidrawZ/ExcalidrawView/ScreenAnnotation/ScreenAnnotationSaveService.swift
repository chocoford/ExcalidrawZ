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
        format: ScreenAnnotationSaveFormat
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
            properties: format.bitmapProperties
        ) else {
            throw SaveError.imageEncodingFailed(format)
        }
        return data
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

    @discardableResult
    static func saveToDownloads(
        _ data: Data,
        format: ScreenAnnotationSaveFormat
    ) throws -> URL {
        let downloads = FileManager.default.urls(
            for: .downloadsDirectory,
            in: .userDomainMask
        )[0]
        let url = uniqueURL(in: downloads, format: format)
        try data.write(to: url, options: .atomic)
        return url
    }

    @discardableResult
    static func saveToCustomLocation(
        _ data: Data,
        format: ScreenAnnotationSaveFormat,
        above annotationWindow: NSWindow?
    ) throws -> URL? {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [format.contentType]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = defaultFilename(format: format)
        if let annotationWindow {
            panel.level = NSWindow.Level(
                rawValue: annotationWindow.level.rawValue + 1
            )
        }

        guard panel.runModal() == .OK, let url = panel.url else {
            return nil
        }
        try data.write(to: url, options: .atomic)
        return url
    }

    private static func uniqueURL(
        in directory: URL,
        format: ScreenAnnotationSaveFormat
    ) -> URL {
        let base = defaultFilename(format: format)
        var candidate = directory.appendingPathComponent(base)
        var suffix = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            let stem = (base as NSString).deletingPathExtension
            candidate = directory.appendingPathComponent(
                "\(stem) \(suffix).\(format.fileExtension)"
            )
            suffix += 1
        }
        return candidate
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
