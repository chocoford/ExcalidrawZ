#if os(macOS)
import AppKit
import QuartzCore
import SwiftUI

@MainActor
final class PaywallPanelController: NSObject, NSWindowDelegate {
    static let shared = PaywallPanelController()

    struct Actions {
        let dismiss: @MainActor () -> Void
        let updateProtection: @MainActor (Bool) -> Void
    }

    private struct Host {
        weak var window: NSWindow?
        let makeContent: (Actions) -> AnyView
    }

    var onDismiss: (() -> Void)?

    private var hosts: [Int: Host] = [:]
    private var panel: PaywallPanel?
    private var session = PaywallPanelSession()
    private var isPresentationRequested = false
    private weak var requestedOwner: NSWindow?
    private var focusCheckTask: Task<Void, Never>?
    private var observers: [NSObjectProtocol] = []
    private var clickMonitor: Any?

    func register(window: NSWindow, makeContent: @escaping (Actions) -> AnyView) {
        hosts = hosts.filter { $0.value.window != nil }
        hosts[window.windowNumber] = Host(window: window, makeContent: makeContent)
        if isPresentationRequested, panel == nil {
            present(from: requestedOwner)
        }
    }

    func unregister(window: NSWindow) {
        hosts[window.windowNumber] = nil
        if panel?.parent === window {
            dismiss()
        }
    }

    func present(from sourceWindow: NSWindow?) {
        isPresentationRequested = true
        requestedOwner = sourceWindow

        if let panel {
            if let owner = host(for: sourceWindow)?.window,
               owner !== panel.parent,
               !session.hasProtectedInteractions, panel.attachedSheet == nil {
                // Replace the host without publishing a dismissal to Math Input's restore flow.
                dismiss(notify: false)
                isPresentationRequested = true
                requestedOwner = sourceWindow
            } else {
                focusCheckTask?.cancel()
                (panel.attachedSheet ?? panel).makeKeyAndOrderFront(nil)
                return
            }
        }

        guard let host = host(for: sourceWindow), let owner = host.window else { return }
        let id = session.begin()
        let actions = Actions(
            dismiss: { [weak self] in self?.dismiss(sessionID: id) },
            updateProtection: { [weak self] isBeginning in
                guard let self, self.session.id == id else { return }
                self.session.updateProtection(isBeginning, for: id)
                if !isBeginning { self.scheduleFocusCheck() }
            }
        )
        let panel = PaywallPanel(onCancel: actions.dismiss)
        self.panel = panel
        panel.delegate = self

        let naturalSize = NSSize(width: 1040, height: 650)
        let visibleFrame = (owner.screen ?? NSScreen.main)?.visibleFrame ?? owner.frame
        let scale = min(1, max(0.1, min(
            (visibleFrame.width - 32) / naturalSize.width,
            (visibleFrame.height - 32) / naturalSize.height
        )))
        let size = NSSize(width: naturalSize.width * scale, height: naturalSize.height * scale)
        let hostingController = NSHostingController(rootView:
            host.makeContent(actions)
                .frame(width: naturalSize.width, height: naturalSize.height)
                .scaleEffect(scale)
                .frame(width: size.width, height: size.height)
                .clipped()
        )
        hostingController.sizingOptions = []
        hostingController.safeAreaRegions = []

        // The window sizes this AppKit view. SwiftUI only lays out its child content.
        let contentController = NSViewController()
        let contentView = NSView(frame: NSRect(origin: .zero, size: size))
        contentController.view = contentView
        contentController.addChild(hostingController)
        hostingController.view.frame = contentView.bounds
        hostingController.view.autoresizingMask = [.width, .height]
        contentView.addSubview(hostingController.view)
        panel.contentViewController = contentController

        let origin = NSPoint(
            x: min(max(owner.frame.midX - size.width / 2, visibleFrame.minX + 16), visibleFrame.maxX - size.width - 16),
            y: min(max(owner.frame.midY - size.height / 2, visibleFrame.minY + 16), visibleFrame.maxY - size.height - 16)
        )
        let frame = NSRect(origin: origin, size: size)
        let shouldAnimate = !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        panel.alphaValue = shouldAnimate ? 0 : 1
        panel.setFrame(frame, display: false)
        owner.addChildWindow(panel, ordered: .above)
        observeFocus(owner: owner)
        panel.makeKeyAndOrderFront(nil)

        if shouldAnimate {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.18
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                panel.animator().alphaValue = 1
            }
        }
    }

    func dismiss() {
        dismiss(notify: true)
    }

    private func dismiss(notify: Bool) {
        guard isPresentationRequested || panel != nil else { return }
        if let id = session.id { _ = session.end(id) }
        isPresentationRequested = false
        requestedOwner = nil
        focusCheckTask?.cancel()
        focusCheckTask = nil
        observers.forEach(NotificationCenter.default.removeObserver)
        observers.removeAll()
        if let clickMonitor {
            NSEvent.removeMonitor(clickMonitor)
            self.clickMonitor = nil
        }
        let closingPanel = panel
        panel = nil
        if let closingPanel {
            closingPanel.parent?.removeChildWindow(closingPanel)
            closingPanel.close()
            closingPanel.contentViewController = nil
        }
        if notify { onDismiss?() }
    }

    private func dismiss(sessionID: UUID) {
        guard session.id == sessionID else { return }
        dismiss()
    }

    func windowDidResignKey(_ notification: Notification) {
        guard notification.object as? NSWindow === panel else { return }
        scheduleFocusCheck()
    }

    func windowWillClose(_ notification: Notification) {
        guard notification.object as? NSWindow === panel else { return }
        dismiss()
    }

    private func host(for sourceWindow: NSWindow?) -> Host? {
        var candidate = sourceWindow
        while let window = candidate {
            if let host = hosts[window.windowNumber], host.window != nil { return host }
            candidate = window.sheetParent ?? window.parent
        }
        if let mainWindow = NSApp.mainWindow, let host = hosts[mainWindow.windowNumber] { return host }
        return NSApp.orderedWindows.compactMap { hosts[$0.windowNumber] }.first
    }

    private func observeFocus(owner: NSWindow) {
        guard let id = session.id else { return }
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.session.id == id else { return }
                self.scheduleFocusCheck()
            }
        })
        observers.append(center.addObserver(forName: NSWindow.willCloseNotification, object: owner, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.dismiss(sessionID: id) }
        })
        clickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] event in
            guard let self, self.session.id == id, let clickedWindow = event.window,
                  !self.belongsToPanel(clickedWindow) else { return event }
            self.scheduleFocusCheck()
            return event
        }
    }

    private func scheduleFocusCheck() {
        guard let id = session.id else { return }
        focusCheckTask?.cancel()
        focusCheckTask = Task { @MainActor [weak self] in
            // AppKit changes the key window after resign-key and sheet notifications.
            do { try await Task.sleep(for: .milliseconds(80)) } catch { return }
            guard let self, self.session.id == id, let panel = self.panel else { return }
            if self.session.shouldDismiss(
                isApplicationActive: NSApp.isActive,
                keyWindowBelongsToPanel: self.belongsToPanel(NSApp.keyWindow),
                hasAttachedSheet: panel.attachedSheet != nil || NSApp.modalWindow != nil
            ) {
                self.dismiss(sessionID: id)
            }
        }
    }

    private func belongsToPanel(_ window: NSWindow?) -> Bool {
        var candidate = window
        while let window = candidate {
            if window === panel { return true }
            candidate = window.sheetParent ?? window.parent
        }
        return false
    }
}

private final class PaywallPanel: NSPanel {
    private let onCancel: @MainActor () -> Void

    init(onCancel: @escaping @MainActor () -> Void) {
        self.onCancel = onCancel
        super.init(contentRect: .zero, styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        animationBehavior = .none
        standardWindowButton(.closeButton)?.isHidden = true
        standardWindowButton(.miniaturizeButton)?.isHidden = true
        standardWindowButton(.zoomButton)?.isHidden = true
        isReleasedWhenClosed = false
        isFloatingPanel = false
        level = .normal
        becomesKeyOnlyIfNeeded = false
        // The controller handles deactivation so StoreKit confirmation can keep the panel alive.
        hidesOnDeactivate = false
        collectionBehavior = [.fullScreenAuxiliary, .transient, .ignoresCycle]
        isMovableByWindowBackground = true
        tabbingMode = .disallowed
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func cancelOperation(_ sender: Any?) { onCancel() }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
#endif
