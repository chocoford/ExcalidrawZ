#if os(macOS)
import AppKit
import ScreenCaptureKit

enum ScreenAnnotationCaptureService {
    @MainActor
    static func capture(_ screen: NSScreen) async throws -> NSImage? {
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

        let currentProcess = content.applications.first {
            $0.processID == ProcessInfo.processInfo.processIdentifier
        }
        let filter: SCContentFilter
        if let currentProcess {
            filter = SCContentFilter(
                display: display,
                excludingApplications: [currentProcess],
                exceptingWindows: []
            )
        } else {
            filter = SCContentFilter(display: display, excludingWindows: [])
        }

        let configuration = SCStreamConfiguration()
        configuration.width = Int(screen.frame.width * screen.backingScaleFactor)
        configuration.height = Int(screen.frame.height * screen.backingScaleFactor)
        configuration.showsCursor = false

        let image = try await SCScreenshotManager.captureImage(
            contentFilter: filter,
            configuration: configuration
        )
        return NSImage(cgImage: image, size: screen.frame.size)
    }
}
#endif
