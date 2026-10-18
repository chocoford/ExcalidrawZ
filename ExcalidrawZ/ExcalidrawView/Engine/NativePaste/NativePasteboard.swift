import Foundation
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif

enum NativePasteboard {
    private static let preferredImageTypes = [
        UTType.heic.identifier, UTType.heif.identifier,
        UTType.png.identifier, UTType.tiff.identifier, UTType.jpeg.identifier,
    ]

    static func isImageFile(name: String, mimeType: String = "") -> Bool {
        if mimeType.lowercased().hasPrefix("image/") { return true }
        return UTType(filenameExtension: (name as NSString).pathExtension)?
            .conforms(to: .image) == true
    }

    private static func imageTypes(in types: [String]) -> [String] {
        let images = types.filter { UTType($0)?.conforms(to: .image) == true }
        return preferredImageTypes.filter(images.contains)
            + images.filter { !preferredImageTypes.contains($0) }
    }

#if os(macOS)
    @MainActor
    static func readImages(from pasteboard: NSPasteboard = .general) -> [NativePasteImageSource] {
        var sources: [NativePasteImageSource] = []
        // Reading NSURL objects also obtains the sandbox's pasted-file access.
        // NSPasteboardItem keeps non-URL image items in their original positions.
        let items = pasteboard.readObjects(
            forClasses: [NSURL.self, NSPasteboardItem.self],
            options: [.urlReadingFileURLsOnly: true]
        ) ?? []
        for value in items {
            if let url = value as? URL, url.isFileURL {
                // Finder can also supply a preview; read the original file instead.
                guard isImageFile(name: url.lastPathComponent) else { return [] }
                sources.append(.fileURL(url))
                continue
            }
            guard let item = value as? NSPasteboardItem else { continue }
            for type in imageTypes(in: item.types.map(\.rawValue)) {
                if let data = item.data(forType: .init(type)) {
                    sources.append(.data(data))
                    break
                }
            }
        }
        return sources
    }
#elseif os(iOS)
    @MainActor
    static func readImages(from pasteboard: UIPasteboard = .general) -> [NativePasteImageSource] {
        var sources: [NativePasteImageSource] = []
        for (index, item) in pasteboard.items.enumerated() {
            if let value = item[UTType.fileURL.identifier],
               let url = (value as? URL) ?? (value as? String).flatMap(URL.init(string:)),
               url.isFileURL {
                guard isImageFile(name: url.lastPathComponent) else { return [] }
                sources.append(.fileURL(url))
                continue
            }
            for type in imageTypes(in: Array(item.keys).sorted()) {
                if let image = item[type] as? UIImage {
                    let orientation = exifOrientation(image.imageOrientation)
                    if let bitmap = image.cgImage {
                        sources.append(.bitmap(bitmap, orientation: orientation))
                        break
                    }
                    if let data = image.pngData() {
                        sources.append(.data(data, orientation: orientation))
                        break
                    }
                }
                if let data = (item[type] as? Data) ?? pasteboard.data(
                    forPasteboardType: type, inItemSet: IndexSet(integer: index)
                )?.first {
                    sources.append(.data(data))
                    break
                }
            }
        }
        return sources
    }

    private static func exifOrientation(_ orientation: UIImage.Orientation) -> UInt32 {
        switch orientation {
            case .up: 1
            case .upMirrored: 2
            case .down: 3
            case .downMirrored: 4
            case .leftMirrored: 5
            case .right: 6
            case .rightMirrored: 7
            case .left: 8
            @unknown default: 1
        }
    }
#endif
}
