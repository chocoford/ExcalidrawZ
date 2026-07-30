#if os(macOS)
import AppKit
import CoreGraphics
import SwiftUI

@MainActor
final class ScreenCapturePermissionGuideController {
    private static let systemSettingsBundleIdentifiers = [
        "com.apple.systempreferences",
        "com.apple.SystemSettings",
    ]
    private static let settingsURL = URL(
        string:
            "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
    )

    private var windowController: NSWindowController?
    private var hostingController:
        NSHostingController<ScreenCapturePermissionGuideView>?
    private var workspaceObserver: NSObjectProtocol?
    private var trackingTimer: Timer?
    private var activationTimeoutTask: Task<Void, Never>?
    private var isAwaitingSystemSettings = false

    func present() {
        isAwaitingSystemSettings = true
        observeApplicationActivationIfNeeded()
        if let settingsURL = Self.settingsURL {
            NSWorkspace.shared.open(settingsURL)
        }
        activationTimeoutTask?.cancel()
        activationTimeoutTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(15))
            guard !Task.isCancelled,
                  self?.isAwaitingSystemSettings == true
            else {
                return
            }
            self?.dismiss()
        }
        updateForFrontmostApplication()
    }

    private func observeApplicationActivationIfNeeded() {
        guard workspaceObserver == nil else { return }
        workspaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.updateForFrontmostApplication()
            }
        }
    }

    private func updateForFrontmostApplication() {
        guard isAwaitingSystemSettings || windowController != nil else {
            return
        }
        guard let application = NSWorkspace.shared.frontmostApplication,
              Self.isSystemSettings(application)
        else {
            return
        }

        let processIdentifier = application.processIdentifier
        startTracking(processIdentifier: processIdentifier)
        attachGuideIfPossible(processIdentifier: processIdentifier)
    }

    private func attachGuideIfPossible(
        processIdentifier: pid_t
    ) {
        guard let settingsFrame = Self.frontWindowFrame(
            processIdentifier: processIdentifier
        ) else {
            return
        }

        isAwaitingSystemSettings = false
        activationTimeoutTask?.cancel()
        activationTimeoutTask = nil
        showGuideIfNeeded()
        updateGuideFrame(settingsFrame: settingsFrame)
        if windowController?.window?.isVisible != true {
            windowController?.window?.orderFrontRegardless()
        }
    }

    private func showGuideIfNeeded() {
        guard windowController == nil else { return }

        let panel = NSPanel(
            contentRect: CGRect(
                origin: .zero,
                size: CGSize(width: 520, height: 112)
            ),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.fullScreenAuxiliary, .moveToActiveSpace]
        let hostingController = NSHostingController(
            rootView: ScreenCapturePermissionGuideView {
                self.dismiss()
            }
        )
        panel.contentViewController = hostingController

        let windowController = NSWindowController(window: panel)
        self.hostingController = hostingController
        self.windowController = windowController
    }

    private func startTracking(processIdentifier: pid_t) {
        trackingTimer?.invalidate()
        trackingTimer = Timer.scheduledTimer(
            withTimeInterval: 0.25,
            repeats: true
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self,
                      let application = NSRunningApplication(
                        processIdentifier: processIdentifier
                      ),
                      !application.isTerminated
                else {
                    self?.dismiss()
                    return
                }
                self.attachGuideIfPossible(
                    processIdentifier: processIdentifier
                )
            }
        }
    }

    private func updateGuideFrame(settingsFrame: CGRect) {
        guard let panel = windowController?.window,
              let hostingController
        else {
            return
        }

        let guideHeight = ceil(
            hostingController.sizeThatFits(
                in: CGSize(
                    width: settingsFrame.width,
                    height: 400
                )
            ).height
        )
        panel.setFrame(
            CGRect(
                x: settingsFrame.minX,
                y: settingsFrame.minY - guideHeight,
                width: settingsFrame.width,
                height: guideHeight
            ),
            display: true
        )
    }

    private func dismiss() {
        isAwaitingSystemSettings = false
        activationTimeoutTask?.cancel()
        activationTimeoutTask = nil
        trackingTimer?.invalidate()
        trackingTimer = nil
        windowController?.close()
        windowController = nil
        hostingController = nil
        if let workspaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(
                workspaceObserver
            )
            self.workspaceObserver = nil
        }
    }

    private static func isSystemSettings(
        _ application: NSRunningApplication
    ) -> Bool {
        guard let bundleIdentifier = application.bundleIdentifier else {
            return false
        }
        return systemSettingsBundleIdentifiers.contains(bundleIdentifier)
    }

    private static func frontWindowFrame(
        processIdentifier: pid_t
    ) -> CGRect? {
        guard let windowInfo = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else {
            return nil
        }

        let bounds = windowInfo.compactMap { info -> CGRect? in
            guard let ownerPID = info[kCGWindowOwnerPID as String]
                    as? NSNumber,
                  ownerPID.int32Value == processIdentifier,
                  let layer = info[kCGWindowLayer as String] as? NSNumber,
                  layer.intValue == 0,
                  let bounds = info[kCGWindowBounds as String]
                    as? NSDictionary,
                  let frame = CGRect(
                    dictionaryRepresentation: bounds
                ),
                  frame.width > 300,
                  frame.height > 200
            else {
                return nil
            }
            return frame
        }
        guard let quartzFrame = bounds.max(by: {
            $0.width * $0.height < $1.width * $1.height
        }) else {
            return nil
        }

        let primaryScreenMaxY = NSScreen.screens.first?.frame.maxY ?? 0
        return CGRect(
            x: quartzFrame.minX,
            y: primaryScreenMaxY - quartzFrame.maxY,
            width: quartzFrame.width,
            height: quartzFrame.height
        )
    }
}
#endif
