#if os(macOS)
import AppKit
import SwiftUI

@MainActor
final class ScreenAnnotationController {
    static let shared = ScreenAnnotationController()

    private var windowController: NSWindowController?
    private var presentationTask: Task<Void, Never>?
    private var captureTask: Task<Void, Never>?
    private var escapeMonitor: Any?

    var isPresented: Bool {
        windowController != nil || presentationTask != nil
    }

    func toggle() {
        if isPresented {
            dismiss()
        } else {
            presentationTask = Task { @MainActor in
                defer { presentationTask = nil }
                await present()
            }
        }
    }

    func dismiss() {
        presentationTask?.cancel()
        presentationTask = nil
        captureTask?.cancel()
        captureTask = nil

        if let escapeMonitor {
            NSEvent.removeMonitor(escapeMonitor)
            self.escapeMonitor = nil
        }

        windowController?.close()
        windowController = nil
    }

    private func present() async {
        let mouseLocation = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) })
            ?? NSScreen.main else {
            return
        }

        let backgroundImage: NSImage?
        do {
            backgroundImage = try await ScreenAnnotationCaptureService.capture(screen)
        } catch {
            backgroundImage = nil
        }
        guard !Task.isCancelled else { return }

        let session = ScreenAnnotationSession(
            frozenBackgroundImage: backgroundImage
        )
        let rootView = ScreenAnnotationView(
            session: session,
            onToggleFreeze: { [weak self] in
                self?.toggleFreeze(session: session, screen: screen)
            },
            onClose: { [weak self] in
                self?.dismiss()
            }
        )

        let panel = ScreenAnnotationPanel(screen: screen)
        let hostingView = NSHostingView(rootView: rootView)
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor
        panel.contentView = hostingView

        let windowController = NSWindowController(window: panel)
        self.windowController = windowController
        installEscapeMonitor()

        panel.orderFrontRegardless()
        panel.makeKey()
    }

    private func toggleFreeze(session: ScreenAnnotationSession, screen: NSScreen) {
        if session.isFrozen {
            captureTask?.cancel()
            captureTask = nil
            session.resumeLiveBackground()
            return
        }

        guard session.beginBackgroundCapture() else { return }
        captureTask = Task { @MainActor [weak self, weak session] in
            defer { self?.captureTask = nil }
            do {
                let image = try await ScreenAnnotationCaptureService.capture(screen)
                guard !Task.isCancelled else { return }
                session?.finishBackgroundCapture(image)
            } catch {
                session?.finishBackgroundCapture(nil)
            }
        }
    }

    private func installEscapeMonitor() {
        escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) {
            [weak self] event in
            guard event.keyCode == 53 else { return event }
            self?.dismiss()
            return nil
        }
    }
}

private final class ScreenAnnotationPanel: NSPanel {
    init(screen: NSScreen) {
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
}
#endif
