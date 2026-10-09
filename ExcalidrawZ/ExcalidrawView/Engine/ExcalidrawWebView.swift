//
//  ExcalidrawWebView.swift
//  ExcalidrawZ
//
//  Created by Chocoford on 5/2/26.
//

import Foundation
import SwiftUI
import WebKit
import Combine
import Logging
import QuartzCore
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#endif
#if os(iOS)
import UIKit
#endif

class ExcalidrawWebView: WKWebView {
    var shouldHandleInput = true
    var nativeInteractionEnabled = true {
        didSet {
            guard nativeInteractionEnabled != oldValue else { return }
#if os(macOS)
            window?.invalidateCursorRects(for: self)
#endif
        }
    }
#if os(macOS)
    private var isVisibilityUpdateScheduled = false
#endif
#if os(iOS)
    private var indirectScrollForwarder: ExcalidrawIndirectScrollForwarder?
#endif
    
    enum ToolbarActionKey {
        case number(Int)
        case char(Character)
        case space, escape
    }
    var toolbarActionHandler: (ToolbarActionKey) -> Void
    
    init(
        frame: CGRect,
        configuration: WKWebViewConfiguration,
        toolbarActionHandler: @escaping (ToolbarActionKey) -> Void
    ) {
        self.toolbarActionHandler = toolbarActionHandler
        super.init(frame: frame, configuration: configuration)
#if canImport(UIKit)
        self.scrollView.isScrollEnabled = false
        self.scrollView.backgroundColor = .clear
#if os(iOS)
        self.indirectScrollForwarder = ExcalidrawIndirectScrollForwarder(webView: self)
#endif
#endif
    }
    
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func updateNativeInteraction(enabled: Bool) {
        nativeInteractionEnabled = enabled
#if os(macOS)
        scheduleVisibilityUpdate()
#elseif os(iOS)
        isHidden = !enabled
        isUserInteractionEnabled = enabled
#endif
    }

#if os(macOS)
    private func scheduleVisibilityUpdate() {
        guard !isVisibilityUpdateScheduled,
              isHidden != !nativeInteractionEnabled else { return }
        isVisibilityUpdateScheduled = true
        // Hiding a focused NSView navigates the key-view loop and can query
        // SwiftUI layout. Defer it beyond updateNSView to avoid re-entering
        // AttributeGraph, and read the latest state if the file changed again.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.isVisibilityUpdateScheduled = false
            let shouldHide = !self.nativeInteractionEnabled
            guard self.isHidden != shouldHide else { return }
            self.isHidden = shouldHide
        }
    }
#endif

#if canImport(UIKit)
    override var safeAreaInsets: UIEdgeInsets { .zero }
#endif
    
#if canImport(AppKit)
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard nativeInteractionEnabled else { return nil }
        return super.hitTest(point)
    }

    override func resetCursorRects() {
        guard nativeInteractionEnabled else { return }
        super.resetCursorRects()
    }

    override func keyDown(with event: NSEvent) {
        if shouldHandleInput,
           let char = event.characters,
           char.count == 1,
           let character = char.first {
            if let num = Int(char), num >= 0, num <= 9 {
                self.toolbarActionHandler(.number(num))
            } else if ExcalidrawTool.allCases.compactMap({ $0.keyEquivalent }).contains(character) {
                self.toolbarActionHandler(.char(character))
            } else if character == " " {
                // TODO: migrate to excalidrawZHelper
                self.toolbarActionHandler(.space)
            } else if character == "q" {
                // TODO: migrate to excalidrawZHelper
                self.toolbarActionHandler(.char("q"))
            } else {
                super.keyDown(with: event)
            }
        } else {
            super.keyDown(with: event)
        }
    }
#endif

#if os(iOS)
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        guard nativeInteractionEnabled else { return false }
        return super.point(inside: point, with: event)
    }
#endif
}

#if os(iOS)
private final class ExcalidrawIndirectScrollForwarder: NSObject, UIGestureRecognizerDelegate {
    private weak var webView: WKWebView?
    private weak var scrollRecognizer: UIPanGestureRecognizer?
    private weak var pinchRecognizer: UIPinchGestureRecognizer?
    private let pinchWheelDeltaMultiplier: CGFloat = 54

    init(webView: WKWebView) {
        self.webView = webView
        super.init()

        let scrollRecognizer = UIPanGestureRecognizer(
            target: self,
            action: #selector(handleIndirectScroll(_:))
        )
        scrollRecognizer.allowedScrollTypesMask = .all
        scrollRecognizer.cancelsTouchesInView = false
        scrollRecognizer.delaysTouchesBegan = false
        scrollRecognizer.delaysTouchesEnded = false
        scrollRecognizer.delegate = self
        webView.addGestureRecognizer(scrollRecognizer)
        self.scrollRecognizer = scrollRecognizer

        let pinchRecognizer = UIPinchGestureRecognizer(
            target: self,
            action: #selector(handleIndirectPinch(_:))
        )
        pinchRecognizer.cancelsTouchesInView = false
        pinchRecognizer.delaysTouchesBegan = false
        pinchRecognizer.delaysTouchesEnded = false
        pinchRecognizer.delegate = self
        webView.addGestureRecognizer(pinchRecognizer)
        self.pinchRecognizer = pinchRecognizer
    }

    @objc private func handleIndirectScroll(_ recognizer: UIPanGestureRecognizer) {
        guard recognizer.state == .began || recognizer.state == .changed,
              let webView else {
            return
        }

        let translation = recognizer.translation(in: webView)
        recognizer.setTranslation(.zero, in: webView)

        guard abs(translation.x) > 0.01 || abs(translation.y) > 0.01 else {
            return
        }

        let location = recognizer.location(in: webView)
        dispatchWheelEvent(
            deltaX: -translation.x,
            deltaY: -translation.y,
            location: location,
            in: webView
        )
    }

    @objc private func handleIndirectPinch(_ recognizer: UIPinchGestureRecognizer) {
        guard recognizer.state == .began || recognizer.state == .changed,
              let webView else {
            recognizer.scale = 1
            return
        }

        let scale = recognizer.scale
        recognizer.scale = 1

        guard scale > 0, scale.isFinite else { return }

        let deltaY = -log(scale) * pinchWheelDeltaMultiplier
        guard abs(deltaY) > 0.01 else { return }

        dispatchWheelEvent(
            deltaX: 0,
            deltaY: deltaY,
            location: recognizer.location(in: webView),
            in: webView,
            ctrlKey: true
        )
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        true
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldReceive event: UIEvent
    ) -> Bool {
        if gestureRecognizer === scrollRecognizer {
            return event.type == .scroll
        }

        if gestureRecognizer === pinchRecognizer {
            return event.type == .transform
        }

        return false
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldReceive touch: UITouch
    ) -> Bool {
        false
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldReceive press: UIPress
    ) -> Bool {
        false
    }

    private func dispatchWheelEvent(
        deltaX: CGFloat,
        deltaY: CGFloat,
        location: CGPoint,
        in webView: WKWebView,
        ctrlKey: Bool = false
    ) {
        let script = """
        (() => {
            const clientX = Math.max(0, Math.min(window.innerWidth, \(Self.javascriptNumber(location.x))));
            const clientY = Math.max(0, Math.min(window.innerHeight, \(Self.javascriptNumber(location.y))));
            const target = document.elementFromPoint(clientX, clientY)
                || document.querySelector(".excalidraw-container")
                || document.body;

            if (!target) {
                return false;
            }

            const event = new WheelEvent("wheel", {
                bubbles: true,
                cancelable: true,
                composed: true,
                clientX,
                clientY,
                screenX: clientX,
                screenY: clientY,
                deltaX: \(Self.javascriptNumber(deltaX)),
                deltaY: \(Self.javascriptNumber(deltaY)),
                deltaZ: 0,
                deltaMode: 0,
                ctrlKey: \(ctrlKey ? "true" : "false")
            });

            return target.dispatchEvent(event);
        })();
        """

        webView.evaluateJavaScript(script, completionHandler: nil)
    }

    private static func javascriptNumber(_ value: CGFloat) -> String {
        let number = Double(value)
        return number.isFinite ? String(number) : "0"
    }
}
#endif

extension Notification.Name {
    static let forceReloadExcalidrawFile = Notification.Name("ForceReloadExcalidrawFile")
}


/// Minimal wrapper to bridge WKWebView to SwiftUI
struct ExcalidrawViewRepresentable {
    @EnvironmentObject private var core: ExcalidrawCore
    var nativeInteractionEnabled: Bool = true
    
    func makeExcalidrawWebView(context: Context) -> ExcalidrawWebView {
        let webView = context.coordinator.webView
        webView.updateNativeInteraction(enabled: nativeInteractionEnabled)
        return webView
    }
    
    func updateExcalidrawWebView(_ webView: ExcalidrawWebView, context: Context) {
        webView.updateNativeInteraction(enabled: nativeInteractionEnabled)
    }
    
    func makeCoordinator() -> ExcalidrawCore {
        return core
    }
}

#if os(macOS)
extension ExcalidrawViewRepresentable: NSViewRepresentable {
    
    func makeNSView(context: Context) -> ExcalidrawCanvasHostView {
        let host = ExcalidrawCanvasHostView()
        host.attach(makeExcalidrawWebView(context: context))
        return host
    }
    
    func updateNSView(_ host: ExcalidrawCanvasHostView, context: Context) {
        let webView = context.coordinator.webView
        host.attach(webView)
        updateExcalidrawWebView(webView, context: context)
    }

    func sizeThatFits(
        _ proposal: ProposedViewSize,
        nsView: ExcalidrawCanvasHostView,
        context: Context
    ) -> CGSize? {
        // Always answer probes here, including unspecified/infinite proposals.
        // Returning nil would delegate sizing back to the native Auto Layout subtree.
        nsView.sizeForProposal(proposal)
    }

    static func dismantleNSView(_ host: ExcalidrawCanvasHostView, coordinator: ExcalidrawCore) {
        host.detach()
    }
}

final class ExcalidrawCanvasHostView: NSView {
    private weak var attachedWebView: ExcalidrawWebView?
    private var isViewportUpdateScheduled = false

    override var isFlipped: Bool { true }

    func sizeForProposal(_ proposal: ProposedViewSize) -> CGSize {
        func dimension(_ proposed: CGFloat?, fallback: CGFloat) -> CGFloat {
            if let proposed, proposed.isFinite {
                return max(0, proposed)
            }
            return fallback.isFinite ? max(0, fallback) : 0
        }

        // Sizing is a read-only operation; it must not query fittingSize or
        // lay out WebKit at the minimum/ideal/maximum measurement sizes.
        return CGSize(
            width: dimension(proposal.width, fallback: bounds.width),
            height: dimension(proposal.height, fallback: bounds.height)
        )
    }

    func attach(_ webView: ExcalidrawWebView) {
        guard attachedWebView !== webView || webView.superview !== self else { return }
        detach()
        webView.removeFromSuperview()
        // NavigationSplitView temporarily lays out its native subtree at the
        // minimum size while measuring. Neither constraints nor autoresizing
        // may forward those intermediate frames to WebKit's web process.
        autoresizesSubviews = false
        webView.translatesAutoresizingMaskIntoConstraints = true
        webView.autoresizingMask = []
        addSubview(webView)
        attachedWebView = webView
        scheduleViewportUpdate()
    }

    func detach() {
        if attachedWebView?.superview === self {
            attachedWebView?.removeFromSuperview()
        }
        attachedWebView = nil
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let hitView = super.hitTest(point), hitView !== self else { return nil }
        return hitView
    }

    override var frame: NSRect {
        didSet {
            if frame.size != oldValue.size { scheduleViewportUpdate() }
        }
    }

    override var bounds: NSRect {
        didSet {
            if bounds != oldValue { scheduleViewportUpdate() }
        }
    }

    override func layout() {
        super.layout()
        scheduleViewportUpdate()
    }

    private func scheduleViewportUpdate() {
        guard attachedWebView != nil, !isViewportUpdateScheduled else { return }
        isViewportUpdateScheduled = true
        // Read bounds when the block runs, not when it is scheduled: a minimum
        // size probe and the actual layout can both happen in the same turn.
        // Common modes also execute while AppKit tracks a window resize.
        RunLoop.main.perform(inModes: [.common]) { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.isViewportUpdateScheduled = false
                self.updateWebViewport()
            }
        }
    }

    private func updateWebViewport() {
        guard let webView = attachedWebView, webView.superview === self,
              bounds.width.isFinite, bounds.height.isFinite,
              bounds.width > 0, bounds.height > 0 else { return }
        guard webView.frame != bounds else { return }
        webView.frame = bounds
    }

    override func viewDidEndLiveResize() {
        super.viewDidEndLiveResize()
        updateWebViewport()
    }
}
#elseif os(iOS)
extension ExcalidrawViewRepresentable: UIViewRepresentable {
    func makeUIView(context: Context) -> ExcalidrawWebView {
        makeExcalidrawWebView(context: context)
    }
    
    func updateUIView(_ uiView: ExcalidrawWebView, context: Context) {
        updateExcalidrawWebView(uiView, context: context)
    }
}
#endif
