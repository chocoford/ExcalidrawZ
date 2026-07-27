#if os(macOS)
import AppKit
import KeyboardShortcuts
import SwiftUI

extension KeyboardShortcuts.Name {
    static let toggleScreenAnnotation = Self(
        "toggleScreenAnnotation",
        initial: .init(.z, modifiers: [.command, .option])
    )
}

@MainActor
final class ScreenAnnotationController {
    static let shared = ScreenAnnotationController()

    private var windowController: NSWindowController?
    private var captureTask: Task<Void, Never>?
    private var shortcutTask: Task<Void, Never>?
    private weak var activeSession: ScreenAnnotationSession?
    private var registeredWindows: [
        ObjectIdentifier: RegisteredWindowContext
    ] = [:]
    private let webRuntime = ScreenAnnotationWebRuntime()
    private let saveCoordinator = ScreenAnnotationSaveCoordinator()

    private init() {
        shortcutTask = Task { @MainActor [weak self] in
            for await _ in KeyboardShortcuts.events(
                .keyUp,
                for: .toggleScreenAnnotation
            ) {
                self?.toggle()
            }
        }
    }

    var isPresented: Bool {
        windowController != nil
    }

    func register(fileState: FileState, for window: NSWindow) {
        registeredWindows[ObjectIdentifier(window)] = RegisteredWindowContext(
            window: window,
            fileState: fileState
        )
    }

    func toggle() {
        if isPresented {
            dismiss()
        } else {
            present()
        }
    }

    func dismiss() {
        captureTask?.cancel()
        captureTask = nil

        let sessionToUnbind = activeSession
        if let sessionToUnbind {
            webRuntime.unbind(sessionToUnbind)
        }
        activeSession = nil
        windowController?.close()
        windowController = nil
    }

    private func present() {
        let mouseLocation = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) })
            ?? NSScreen.main else {
            return
        }
        let fileState = resolvedFileState(for: screen)

        let toolbarOrderData = UserDefaults.standard.data(
            forKey: ExcalidrawToolbarToolOrder.storageKey
        ) ?? Data()
        let toolbarToolOrder = ExcalidrawToolbarToolOrder(
            storedData: toolbarOrderData
        )
        let tools = toolbarToolOrder.tools.filter {
            ![.image, .frame, .webEmbed, .magicFrame].contains($0)
        }
        let session = ScreenAnnotationSession(
            toolbarTools: tools
        )
        activeSession = session
        let toolbarPlacement = ScreenAnnotationToolbarPlacementStore
            .placement(for: screen)
        let rootView = ScreenAnnotationView(
            session: session,
            saveConfiguration: saveCoordinator.configuration,
            webRuntime: webRuntime,
            tools: tools,
            initialToolbarPlacement: toolbarPlacement,
            onToolbarPlacementChange: { placement in
                ScreenAnnotationToolbarPlacementStore.save(
                    placement,
                    for: screen
                )
            },
            onToggleFreeze: { [weak self] in
                self?.toggleFreeze(session: session, screen: screen)
            },
            onSave: {
                [weak self, weak session]
                destination,
                format,
                imageQuality,
                region,
                completion in
                guard let self, let session else {
                    completion(false)
                    return
                }
                self.saveCoordinator.submit(
                    destination: destination,
                    format: format,
                    imageQuality: imageQuality,
                    region: region,
                    session: session,
                    screen: screen,
                    fileState: fileState,
                    annotationWindow: self.windowController?.window,
                    completion: completion
                )
            },
            onClose: { [weak self] in
                self?.dismiss()
            }
        )
        .environment(
            \.managedObjectContext,
            PersistenceController.shared.container.viewContext
        )
        .environmentObject(ItemDragState())

        let panel = ScreenAnnotationPanel(
            screen: screen,
            onCommandEscape: { [weak self] in
                self?.dismiss()
            }
        )
        let hostingView = NSHostingView(rootView: rootView)
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor
        panel.contentView = hostingView

        let windowController = NSWindowController(window: panel)
        self.windowController = windowController

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

        captureBackground(session: session, screen: screen)
    }

    private func captureBackground(
        session: ScreenAnnotationSession,
        screen: NSScreen
    ) {
        guard session.beginBackgroundCapture() else { return }
        let annotationWindowNumber = windowController?.window?.windowNumber
        captureTask = Task { @MainActor [weak self, weak session] in
            defer { self?.captureTask = nil }
            do {
                let image = try await ScreenAnnotationCaptureService.capture(
                    screen,
                    excludingWindowNumber: annotationWindowNumber
                )
                guard !Task.isCancelled else { return }
                session?.finishBackgroundCapture(image)
            } catch {
                session?.finishBackgroundCapture(nil)
            }
        }
    }

    private func resolvedFileState(for screen: NSScreen) -> FileState? {
        registeredWindows = registeredWindows.filter {
            $0.value.window != nil && $0.value.fileState != nil
        }

        if let keyWindow = NSApp.keyWindow,
           keyWindow.screen === screen,
           let fileState = registeredWindows[
               ObjectIdentifier(keyWindow)
           ]?.fileState {
            return fileState
        }
        if let mainWindow = NSApp.mainWindow,
           mainWindow.screen === screen,
           let fileState = registeredWindows[
               ObjectIdentifier(mainWindow)
           ]?.fileState {
            return fileState
        }
        if let context = registeredWindows.values.first(where: {
            $0.window?.screen === screen && $0.window?.isVisible == true
        }) {
            return context.fileState
        }
        if let keyWindow = NSApp.keyWindow,
           let fileState = registeredWindows[
               ObjectIdentifier(keyWindow)
           ]?.fileState {
            return fileState
        }
        if let mainWindow = NSApp.mainWindow,
           let fileState = registeredWindows[
               ObjectIdentifier(mainWindow)
           ]?.fileState {
            return fileState
        }
        return registeredWindows.values.first {
            $0.window?.isVisible == true
        }?.fileState ?? registeredWindows.values.first?.fileState
    }
}

private final class RegisteredWindowContext {
    weak var window: NSWindow?
    weak var fileState: FileState?

    init(window: NSWindow, fileState: FileState) {
        self.window = window
        self.fileState = fileState
    }
}
#endif
