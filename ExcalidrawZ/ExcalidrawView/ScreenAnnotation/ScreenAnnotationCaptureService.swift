#if os(macOS)
import AppKit
import ScreenCaptureKit

enum ScreenAnnotationCaptureService {
    @MainActor
    static func capture(
        _ screen: NSScreen,
        excludingWindowNumber: Int?
    ) async throws -> NSImage? {
        guard #available(macOS 14.0, *) else {
            return nil
        }

        guard let screenNumber = screen.deviceDescription[
            NSDeviceDescriptionKey("NSScreenNumber")
        ] as? NSNumber else {
            return nil
        }
        let displayID = CGDirectDisplayID(screenNumber.uint32Value)

        let content = try await SCShareableContent.current
        guard let display = content.displays.first(where: { $0.displayID == displayID }) else {
            return nil
        }

        let excludedWindows = excludingWindowNumber.flatMap { windowNumber in
            content.windows.first {
                $0.windowID == CGWindowID(windowNumber)
            }
        }.map { [$0] } ?? []
        let filter = SCContentFilter(
            display: display,
            excludingWindows: excludedWindows
        )
        let pixelWidth = Int(screen.frame.width * screen.backingScaleFactor)
        let pixelHeight = Int(screen.frame.height * screen.backingScaleFactor)

        let image: CGImage
        if #available(macOS 26.0, *) {
            let configuration = SCScreenshotConfiguration()
            configuration.width = pixelWidth
            configuration.height = pixelHeight
            configuration.showsCursor = false
            configuration.ignoreShadows = false
            configuration.ignoreClipping = false

            let output = try await SCScreenshotManager.captureScreenshot(
                contentFilter: filter,
                configuration: configuration
            )
            guard let screenshot = output.sdrImage else {
                return nil
            }
            image = screenshot
        } else {
            let configuration = SCStreamConfiguration()
            configuration.width = pixelWidth
            configuration.height = pixelHeight
            configuration.showsCursor = false
            configuration.ignoreShadowsDisplay = false
            configuration.ignoreGlobalClipDisplay = false

            image = try await SCScreenshotManager.captureImage(
                contentFilter: filter,
                configuration: configuration
            )
        }

        return NSImage(cgImage: image, size: screen.frame.size)
    }
}
#endif
