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

        // Keep the executable compatible with the app's macOS 13 deployment
        // target. Referencing macOS 26's SCScreenshotConfiguration currently
        // emits a strong Objective-C class symbol and makes dyld abort before
        // launch on older systems, even when guarded by #available.
        let configuration = SCStreamConfiguration()
        configuration.width = pixelWidth
        configuration.height = pixelHeight
        configuration.showsCursor = false
        configuration.ignoreShadowsDisplay = false
        configuration.ignoreGlobalClipDisplay = false

        let image = try await SCScreenshotManager.captureImage(
            contentFilter: filter,
            configuration: configuration
        )

        return NSImage(cgImage: image, size: screen.frame.size)
    }
}
#endif
