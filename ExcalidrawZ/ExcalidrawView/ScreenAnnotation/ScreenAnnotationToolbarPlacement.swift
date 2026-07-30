#if os(macOS)
import AppKit
import Foundation

struct ScreenAnnotationToolbarPlacement: Codable, Equatable {
    private let normalizedX: Double
    private let normalizedY: Double

    init(center: CGPoint, containerSize: CGSize) {
        normalizedX = Self.normalize(center.x, upperBound: containerSize.width)
        normalizedY = Self.normalize(center.y, upperBound: containerSize.height)
    }

    func center(in containerSize: CGSize) -> CGPoint {
        CGPoint(
            x: normalizedX * containerSize.width,
            y: normalizedY * containerSize.height
        )
    }

    private static func normalize(
        _ value: CGFloat,
        upperBound: CGFloat
    ) -> Double {
        guard upperBound > 0 else { return 0.5 }
        return min(max(Double(value / upperBound), 0), 1)
    }
}

enum ScreenAnnotationToolbarPlacementStore {
    private static let storageKey = "screenAnnotationToolbarPlacements"

    static func placement(
        for screen: NSScreen
    ) -> ScreenAnnotationToolbarPlacement? {
        placements[screenIdentifier(for: screen)]
    }

    static func save(
        _ placement: ScreenAnnotationToolbarPlacement,
        for screen: NSScreen
    ) {
        var placements = placements
        placements[screenIdentifier(for: screen)] = placement
        guard let data = try? JSONEncoder().encode(placements) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }

    private static var placements: [String: ScreenAnnotationToolbarPlacement] {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let placements = try? JSONDecoder().decode(
                  [String: ScreenAnnotationToolbarPlacement].self,
                  from: data
              ) else {
            return [:]
        }
        return placements
    }

    private static func screenIdentifier(for screen: NSScreen) -> String {
        guard let screenNumber = screen.deviceDescription[
            NSDeviceDescriptionKey("NSScreenNumber")
        ] as? NSNumber else {
            return fallbackIdentifier(for: screen)
        }

        let displayID = CGDirectDisplayID(screenNumber.uint32Value)
        guard let uuid = CGDisplayCreateUUIDFromDisplayID(displayID)?
            .takeRetainedValue() else {
            return "display-\(displayID)"
        }
        return CFUUIDCreateString(nil, uuid) as String
    }

    private static func fallbackIdentifier(for screen: NSScreen) -> String {
        let frame = screen.frame
        return [
            screen.localizedName,
            String(Int(frame.width.rounded())),
            String(Int(frame.height.rounded())),
        ].joined(separator: "-")
    }
}
#endif
