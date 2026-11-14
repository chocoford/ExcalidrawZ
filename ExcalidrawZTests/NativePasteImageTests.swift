import CoreImage
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import ExcalidrawZ
#if os(macOS)
import AppKit
#endif

final class NativePasteImageTests: XCTestCase {
    func testPNGPreservesPixelsAndTransparency() throws {
        let pixels: [UInt8] = [255, 0, 0, 255, 128, 0, 0, 128, 0, 0, 0, 0]
        let source = try bitmap(width: 3, height: 1, pixels: pixels)
        let result = try convert(encode(source, type: .png))

        XCTAssertEqual(result.width, 3)
        XCTAssertEqual(result.height, 1)
        XCTAssertEqual(result.bitsPerComponent, 8)
        XCTAssertEqual(result.colorSpace?.name, CGColorSpace.sRGB)
        XCTAssertEqual(try rgba(result), pixels)
    }

    func testOrientationIsBakedIntoPixels() throws {
        let source = try bitmap(width: 2, height: 1, pixels: [255, 0, 0, 255, 0, 255, 0, 255])
        let result = try convert(encode(source, type: .tiff, orientation: 2))

        XCTAssertEqual(try rgba(result), [0, 255, 0, 255, 255, 0, 0, 255])
    }

    func testQuarterTurnPreservesFullOrientedDimensions() throws {
        let source = try bitmap(width: 2, height: 3)
        let result = try convert(encode(source, type: .tiff, orientation: 6))

        XCTAssertEqual(result.width, 3)
        XCTAssertEqual(result.height, 2)
    }

    func testBitmapFallbackHonorsUIKitOrientationWithoutResizing() throws {
        let images = try NativePasteImageConverter.convert([
            .bitmap(try bitmap(width: 4097, height: 3), orientation: 6),
        ])
        let result = try decode(XCTUnwrap(images.first))

        XCTAssertEqual(result.width, 3)
        XCTAssertEqual(result.height, 4097)
    }

    func testWideColorImageIsConvertedToEightBitSRGB() throws {
        let source = try bitmap(
            width: 2, height: 1,
            colorSpace: XCTUnwrap(CGColorSpace(name: CGColorSpace.displayP3))
        )
        let result = try convert(encode(source, type: .png))

        XCTAssertEqual(result.bitsPerComponent, 8)
        XCTAssertEqual(result.colorSpace?.name, CGColorSpace.sRGB)
    }

    func testHEICIsConvertedAtOriginalDimensions() throws {
        let source = try bitmap(width: 96, height: 64)
        let result = try convert(encode(source, type: .heic, orientation: 6))

        XCTAssertEqual(result.width, 64)
        XCTAssertEqual(result.height, 96)
        XCTAssertEqual(result.bitsPerComponent, 8)
        XCTAssertEqual(result.colorSpace?.name, CGColorSpace.sRGB)
    }

    func testHDRHEICIsToneMappedToSDR() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("hdr.heic")
        let hdrSpace = try XCTUnwrap(CGColorSpace(name: CGColorSpace.itur_2100_PQ))
        let linearSpace = try XCTUnwrap(CGColorSpace(name: CGColorSpace.extendedLinearSRGB))
        let color = try XCTUnwrap(CIColor(red: 4, green: 2, blue: 0.5, colorSpace: linearSpace))
        let image = CIImage(color: color)
            .cropped(to: CGRect(x: 0, y: 0, width: 64, height: 32))
        try CIContext().writeHEIF10Representation(of: image, to: url, colorSpace: hdrSpace, options: [:])
        let input = try Data(contentsOf: url)
        let raw = try XCTUnwrap(CIImage(data: input))
        XCTAssertTrue(raw.colorSpace?.isHDR() == true)

        let result = try convert(input)

        XCTAssertEqual(result.width, 64)
        XCTAssertEqual(result.height, 32)
        XCTAssertEqual(result.bitsPerComponent, 8)
        XCTAssertEqual(result.colorSpace?.name, CGColorSpace.sRGB)
        let pixel = try rgba(result)
        // A straight clamp clips both red and green to 255. Tone mapping retains their difference.
        XCTAssertGreaterThan(pixel[0], pixel[1])
        XCTAssertLessThan(pixel[1], 255)
    }

    func testMultipleImagesRetainOrderAndPNGNames() throws {
        let images = try NativePasteImageConverter.convert([
            .data(encode(try bitmap(width: 2, height: 1), type: .png), name: "first.heic"),
            .data(encode(try bitmap(width: 3, height: 1), type: .png), name: "second.heif"),
        ])

        XCTAssertEqual(images.map(\.name), ["first.png", "second.png"])
        XCTAssertEqual(try images.map { try decode($0).width }, [2, 3])
    }

    func testCorruptImageFailsTheBatchInsteadOfDroppingAnImage() throws {
        XCTAssertThrowsError(try NativePasteImageConverter.convert([
            .data(encode(try bitmap(width: 2, height: 1), type: .png)),
            .data(Data("not an image".utf8)),
        ]))
    }

#if os(macOS)
    @MainActor
    func testClipboardPrefersHEICRepresentationAndRetainsItemOrder() throws {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        let first = NSPasteboardItem()
        first.setData(Data([1]), forType: .init(UTType.heic.identifier))
        first.setData(Data([9]), forType: .png)
        let second = NSPasteboardItem()
        second.setData(Data([2]), forType: .tiff)
        pasteboard.writeObjects([first, second])

        let sources = NativePasteboard.readImages(from: pasteboard)

        XCTAssertEqual(sources.count, 2)
        guard case .data(let firstData, _, _) = sources[0],
              case .data(let secondData, _, _) = sources[1] else {
            return XCTFail("Expected one original image representation per clipboard item")
        }
        XCTAssertEqual(firstData, Data([1]))
        XCTAssertEqual(secondData, Data([2]))
    }

    @MainActor
    func testClipboardReadsOriginalFileInsteadOfFinderPreview() throws {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        let item = NSPasteboardItem()
        let url = URL(fileURLWithPath: "/tmp/original.heic")
        item.setString(url.absoluteString, forType: .fileURL)
        item.setData(Data([9]), forType: .png)
        pasteboard.writeObjects([item])

        let sources = NativePasteboard.readImages(from: pasteboard)

        XCTAssertEqual(sources.count, 1)
        guard case .fileURL(let originalURL) = sources[0] else {
            return XCTFail("Expected original file URL")
        }
        XCTAssertEqual(originalURL, url)
    }

    @MainActor
    func testTextAndMixedNonImageFilesFallBackToWebPaste() throws {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        pasteboard.setString("hello", forType: .string)
        XCTAssertTrue(NativePasteboard.readImages(from: pasteboard).isEmpty)

        pasteboard.clearContents()
        let image = NSPasteboardItem()
        image.setData(Data([1]), forType: .png)
        let otherFile = NSPasteboardItem()
        otherFile.setString(URL(fileURLWithPath: "/tmp/document.pdf").absoluteString, forType: .fileURL)
        pasteboard.writeObjects([image, otherFile])
        XCTAssertTrue(NativePasteboard.readImages(from: pasteboard).isEmpty)
    }
#endif

    private func convert(_ data: Data) throws -> CGImage {
        let images = try NativePasteImageConverter.convert([.data(data)])
        return try decode(XCTUnwrap(images.first))
    }

    private func decode(_ image: NativePasteImageConverter.Image) throws -> CGImage {
        XCTAssertEqual(image.mimeType, "image/png")
        XCTAssertTrue(image.dataURL.hasPrefix("data:image/png;base64,"))
        let data = try XCTUnwrap(Data(base64Encoded: String(image.dataURL.dropFirst(22))))
        let source = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
        return try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
    }

    private func bitmap(
        width: Int,
        height: Int,
        colorSpace: CGColorSpace = CGColorSpace(name: CGColorSpace.sRGB)!,
        pixels: [UInt8]? = nil
    ) throws -> CGImage {
        let data = Data(pixels ?? [UInt8](repeating: 255, count: width * height * 4))
        let provider = try XCTUnwrap(CGDataProvider(data: data as CFData))
        return try XCTUnwrap(CGImage(
            width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
            bytesPerRow: width * 4, space: colorSpace,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent
        ))
    }

    private func encode(_ image: CGImage, type: UTType, orientation: Int = 1) throws -> Data {
        let data = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(
            data, type.identifier as CFString, 1, nil
        ))
        CGImageDestinationAddImage(destination, image, [kCGImagePropertyOrientation: orientation] as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return data as Data
    }

    private func rgba(_ image: CGImage) throws -> [UInt8] {
        var pixels = [UInt8](repeating: 0, count: image.width * image.height * 4)
        try pixels.withUnsafeMutableBytes { buffer in
            let context = try XCTUnwrap(CGContext(
                data: buffer.baseAddress, width: image.width, height: image.height,
                bitsPerComponent: 8, bytesPerRow: image.width * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ))
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
        return pixels
    }
}
