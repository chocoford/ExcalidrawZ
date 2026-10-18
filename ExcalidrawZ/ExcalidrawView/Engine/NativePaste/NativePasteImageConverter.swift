import CoreImage
import Foundation
import ImageIO
import UniformTypeIdentifiers

enum NativePasteImageSource: Sendable {
    case data(Data, name: String? = nil, orientation: UInt32? = nil)
    case fileURL(URL)
    case bitmap(CGImage, orientation: UInt32)
}

enum NativePasteImageConverter {
    struct Image: Encodable, Sendable {
        let mimeType = "image/png"
        let dataURL: String
        let name: String
    }

    enum Failure: LocalizedError {
        case decode, render, encode

        var errorDescription: String? {
            NativePasteImageConverter.failureMessage
        }
    }

    static var failureMessage: String {
        String(
            localized: "nativePasteImageConversionFailed",
            defaultValue: "The clipboard image could not be converted."
        )
    }

    static func convert(_ sources: [NativePasteImageSource]) throws -> [Image] {
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
        let context = CIContext(options: [.cacheIntermediates: false])
        return try sources.map { source in
            try Task.checkCancellation()
            return try autoreleasepool {
                switch source {
                    case .data(let data, let name, let orientation):
                        return try convert(
                            data, name: name, orientation: orientation,
                            context: context, colorSpace: colorSpace
                        )
                    case .fileURL(let url):
                        let hasAccess = url.startAccessingSecurityScopedResource()
                        defer {
                            if hasAccess { url.stopAccessingSecurityScopedResource() }
                        }
                        return try convert(
                            Data(contentsOf: url), name: url.lastPathComponent,
                            orientation: nil, context: context, colorSpace: colorSpace
                        )
                    case .bitmap(let bitmap, let orientation):
                        let image = CIImage(cgImage: bitmap, options: [.toneMapHDRtoSDR: true])
                            .oriented(forExifOrientation: Int32(orientation))
                        return try pngImage(
                            from: image, name: nil, context: context, colorSpace: colorSpace
                        )
                }
            }
        }
    }

    private static func convert(
        _ data: Data,
        name: String?,
        orientation: UInt32?,
        context: CIContext,
        colorSpace: CGColorSpace
    ) throws -> Image {
        var options: [CIImageOption: Any] = [
            .applyOrientationProperty: orientation == nil,
            .toneMapHDRtoSDR: true,
        ]
        if #available(macOS 14.0, iOS 17.0, *) {
            // Gain-map images already contain an SDR base representation.
            options[.expandToHDR] = false
        }
        guard var image = CIImage(data: data, options: options) else {
            throw Failure.decode
        }
        if let orientation {
            image = image.oriented(forExifOrientation: Int32(orientation))
        }
        return try pngImage(from: image, name: name, context: context, colorSpace: colorSpace)
    }

    private static func pngImage(
        from image: CIImage,
        name: String?,
        context: CIContext,
        colorSpace: CGColorSpace
    ) throws -> Image {
        // Render the full oriented extent; RGBA8 + sRGB excludes HDR PNG output.
        guard let bitmap = context.createCGImage(
            image, from: image.extent, format: .RGBA8, colorSpace: colorSpace
        ) else {
            throw Failure.render
        }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output, UTType.png.identifier as CFString, 1, nil
        ) else {
            throw Failure.encode
        }
        CGImageDestinationAddImage(destination, bitmap, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw Failure.encode
        }
        let filename = name.map {
            (($0 as NSString).lastPathComponent as NSString).deletingPathExtension + ".png"
        } ?? "clipboard.png"
        return Image(
            dataURL: "data:image/png;base64,\((output as Data).base64EncodedString())",
            name: filename
        )
    }
}
