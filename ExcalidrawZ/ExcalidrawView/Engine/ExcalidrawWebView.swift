//
//  ExcalidrawWebView.swift
//  ExcalidrawZ
//
//  Created by Chocoford on 5/2/26.
//

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
    weak var excalidrawCore: ExcalidrawCore?
    var nativeInteractionEnabled = true {
        didSet {
            guard nativeInteractionEnabled != oldValue else { return }
#if os(macOS)
            window?.invalidateCursorRects(for: self)
#endif
        }
    }
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

#if os(macOS)
extension ExcalidrawWebView {
    private var libraryPasteboardType: NSPasteboard.PasteboardType {
        NSPasteboard.PasteboardType(UTType.excalidrawlibJSON.identifier)
    }

    private func libraryDragData(from pasteboard: NSPasteboard) -> Data? {
        if let data = pasteboard.data(forType: libraryPasteboardType), !data.isEmpty { return data }
        if let type = pasteboard.types?.first(where: { $0.rawValue.lowercased().contains("excalidrawlib") }),
           let data = pasteboard.data(forType: type), !data.isEmpty { return data }
        return nil
    }

    override func wantsPeriodicDraggingUpdates() -> Bool { false }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        (excalidrawCore != nil && libraryDragData(from: sender.draggingPasteboard) != nil) ? .copy : []
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        (excalidrawCore != nil && libraryDragData(from: sender.draggingPasteboard) != nil) ? .copy : []
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let core = excalidrawCore,
              let data = libraryDragData(from: sender.draggingPasteboard) else { return false }
        let dropPoint = self.convert(sender.draggingLocation, from: nil)
        Task { await Self.insertLibraryData(data, core: core, dropPoint: dropPoint) }
        return true
    }

    private static var lastDrop: (hash: Int, date: Date)?

    private static func insertLibraryData(_ data: Data, core: ExcalidrawCore, dropPoint: CGPoint) async {
        let hash = data.hashValue
        if let last = lastDrop, last.hash == hash, Date().timeIntervalSince(last.date) < 1 { return }
        lastDrop = (hash, Date())
        do {
            let library = try JSONDecoder().decode(ExcalidrawLibrary.self, from: data)
            let sourceElements = library.libraryItems.flatMap { $0.elements }
            guard !sourceElements.isEmpty else { return }
            let scenePoint = try? await core.sceneCoords(for: dropPoint)
            let placement: LibraryItemCanvasElementPreprocessor.Placement =
                scenePoint.map { .center(x: $0.x, y: $0.y) } ?? .original
            try await core.addElements(
                LibraryItemCanvasElementPreprocessor.prepare(elements: sourceElements, placement: placement)
            )
        } catch {}
    }
}
#endif


/// Minimal wrapper to bridge WKWebView to SwiftUI
struct ExcalidrawViewRepresentable {
    @EnvironmentObject private var core: ExcalidrawCore
    var nativeInteractionEnabled: Bool = true
    
    func makeExcalidrawWebView(context: Context) -> ExcalidrawWebView {
        let webView = context.coordinator.webView
        updateNativeInteraction(enabled: nativeInteractionEnabled, webView: webView)
        return webView
    }
    
    func updateExcalidrawWebView(_ webView: ExcalidrawWebView, context: Context) {
        updateNativeInteraction(enabled: nativeInteractionEnabled, webView: webView)
    }

    private func updateNativeInteraction(enabled: Bool, webView: ExcalidrawWebView) {
        webView.nativeInteractionEnabled = enabled
        webView.isHidden = !enabled
#if os(iOS)
        webView.isUserInteractionEnabled = enabled
#endif
    }
    
    func makeCoordinator() -> ExcalidrawCore {
        return core
    }
}

#if os(macOS)
extension ExcalidrawViewRepresentable: NSViewRepresentable {
    
    func makeNSView(context: Context) -> ExcalidrawWebView {
        makeExcalidrawWebView(context: context)
    }
    
    func updateNSView(_ nsView: ExcalidrawWebView, context: Context) {
        updateExcalidrawWebView(nsView, context: context)
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
