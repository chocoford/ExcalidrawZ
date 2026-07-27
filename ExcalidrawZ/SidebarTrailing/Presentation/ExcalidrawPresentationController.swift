//
//  ExcalidrawPresentationController.swift
//  ExcalidrawZ
//
//  Created by Codex on 2026/7/27.
//

import SwiftUI

#if os(macOS)
import AppKit
#endif

@MainActor
final class ExcalidrawPresentationController: ObservableObject {
    static let shared = ExcalidrawPresentationController()

    @Published var session: ExcalidrawPresentationSession?

#if os(macOS)
    private var presentationWindow: NSWindow?
#endif

    private init() {}

    func present(
        title: String,
        slides: [ExcalidrawPresentationSlide],
        initialSlideID: String?
    ) {
        guard !slides.isEmpty else { return }
        session = ExcalidrawPresentationSession(
            title: title,
            slides: slides,
            initialSlideID: initialSlideID
        )
#if os(macOS)
        presentMacWindow()
#endif
    }

    func dismiss() {
#if os(macOS)
        let window = presentationWindow
        presentationWindow = nil
#endif
        session = nil
#if os(macOS)
        // Closing an NSHostingView's window from one of its own event callbacks
        // can release the responder before AppKit finishes dispatching the event.
        DispatchQueue.main.async {
            window?.orderOut(nil)
            window?.close()
        }
#endif
    }

#if os(macOS)
    private func presentMacWindow() {
        guard let session else { return }

        if let presentationWindow, presentationWindow.isVisible {
            presentationWindow.title = session.title
            presentationWindow.contentView = presentationContentView(
                for: session
            )
            presentationWindow.makeKeyAndOrderFront(nil)
            return
        }
        presentationWindow = nil

        let screen = NSApp.keyWindow?.screen ?? NSScreen.main
        let window = NSWindow(
            contentRect: screen?.frame ?? .zero,
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false,
            screen: screen
        )
        window.title = session.title
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.backgroundColor = .black
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.fullScreenPrimary]
        window.contentView = presentationContentView(for: session)
        presentationWindow = window
        window.makeKeyAndOrderFront(nil)
        window.toggleFullScreen(nil)
    }

    private func presentationContentView(
        for session: ExcalidrawPresentationSession
    ) -> NSHostingView<ExcalidrawPresentationView> {
        NSHostingView(
            rootView: ExcalidrawPresentationView(
                session: session,
                onDismiss: { [weak self] in
                    self?.dismiss()
                }
            )
        )
    }
#endif
}
