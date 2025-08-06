//
//  CursorHoverView.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 8/5/25.
//

import SwiftUI

#if canImport(AppKit)
import AppKit

class CursorHostingView<Content: View>: NSHostingView<Content> {
    var cursor: NSCursor
    init(cursor: NSCursor, rootView: Content) {
        self.cursor = cursor
        super.init(rootView: rootView)
    }
    
    @MainActor @preconcurrency required dynamic init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    @MainActor @preconcurrency required init(rootView: Content) {
        self.cursor = NSCursor.arrow // Default cursor, can be changed later
        super.init(rootView: rootView)
    }
    
    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: cursor)
    }
}

struct HoverCursorContainer<Content: View>: NSViewRepresentable {
    var cursor: NSCursor
    var rootView: Content
    
    init(
        cursor: NSCursor,
        @ViewBuilder rootView: () -> Content
    ) {
        self.cursor = cursor
        self.rootView = rootView()
    }

    func makeNSView(context: Context) -> CursorHostingView<Content> {
        CursorHostingView(
            cursor: cursor,
            rootView: rootView
        )
    }

    func updateNSView(_ nsView: CursorHostingView<Content>, context: Context) {
        nsView.cursor = cursor
        nsView.rootView = rootView
    }
}

struct HoverCursorModifier: ViewModifier {
    var cursor: NSCursor
    
    func body(content: Content) -> some View {
        HoverCursorContainer(cursor: cursor) {
            content
        }
    }
    
}

//@available(macOS 15.0, *)
//extension PointerStyle {
//    init?(cursor: NSCursor) {
//        switch cursor {
//        case .arrow:
//            self = .default
//        case .pointingHand:
//                self = .
//        case .iBeam:
//            self = .text
//        case .crosshair:
//            self = .crosshair
//        case .resizeLeftRight:
//            self = .resizeLeftRight
//        case .resizeUpDown:
//            self = .resizeUpDown
//        case .resizeDiagonal:
//            self = .resizeDiagonal
//        default:
//            self = .default // Fallback to default for unsupported cursors
//        }
//    }
//}

extension View {
    @ViewBuilder
    public func hoverCursor(_ cursor: NSCursor) -> some View {
        modifier(HoverCursorModifier(cursor: cursor))
//        if #available(macOS 15.0, *), let pointerStyle = PointerStyle(cursor: cursor) {
//            self.pointerStyle(pointerStyle)
//        } else {
//            modifier(HoverCursorModifier(cursor: cursor))
//        }
    }
}
#endif
