#if os(macOS)
import AppKit

final class ScreenAnnotationPanel: NSPanel {
    private let onCommandEscape: () -> Void

    init(
        screen: NSScreen,
        onCommandEscape: @escaping () -> Void
    ) {
        self.onCommandEscape = onCommandEscape
        super.init(
            contentRect: screen.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        collectionBehavior = [.canJoinAllSpaces, .stationary]
        if #available(macOS 26.0, *) {
            collectionBehavior.insert(.canJoinAllApplications)
        } else {
            collectionBehavior.insert(.fullScreenAuxiliary)
        }
        animationBehavior = .none
        acceptsMouseMovedEvents = true
        isFloatingPanel = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        isMovable = false

        // isFloatingPanel resets the level, so shielding must be assigned last.
        level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var canBecomeKey: Bool { true }

    override var canBecomeMain: Bool { false }

    override func sendEvent(_ event: NSEvent) {
        let modifiers = event.modifierFlags.intersection([
            .command,
            .option,
            .control,
            .shift,
        ])
        if event.type == .keyDown,
           event.keyCode == 53,
           modifiers == .command {
            onCommandEscape()
            return
        }
        super.sendEvent(event)
    }
}
#endif
