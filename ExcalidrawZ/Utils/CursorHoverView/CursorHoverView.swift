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
    private var trackingArea: NSTrackingArea?

    init(cursor: NSCursor, rootView: Content) {
        self.cursor = cursor
        super.init(rootView: rootView)
    }
    
    @MainActor @preconcurrency required dynamic init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    @MainActor @preconcurrency required init(rootView: Content) {
        self.cursor = .arrow
        super.init(rootView: rootView)
        addTracking()
    }
    
    /// 短答案：别用 addCursorRect 这一套。
    /// 它在 NSScrollView/SwiftUI.ScrollView 的滚动与视图复用过程中很容易被 AppKit 反复触发、销毁、再创建，配合 SwiftUI 的 NSHostingView 更新时机，常见会炸在「游离视图还在 resetCursorRects / 光标区已失效」这类断言上。
    /// 改用 NSTrackingArea 的 mouseEntered/Exited 或 macOS 15 的 .pointerStyle(...) 就不会因为滚动而崩。
    // override func resetCursorRects() {
    //     super.resetCursorRects()
    //     addCursorRect(bounds, cursor: cursor)
    // }
    
    // 跟随可见区域与尺寸变化，交给 AppKit 调用
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        addTracking()
    }
    
    private func addTracking() {
        if let ta = trackingArea { removeTrackingArea(ta) }
        let options: NSTrackingArea.Options = [
            .mouseEnteredAndExited,
            .inVisibleRect,          // 跟随可见区域，无需手动更新 rect
            .activeInKeyWindow
        ]
        let ta = NSTrackingArea(
            rect: .zero,
            options: options,
            owner: self,
            userInfo: nil
        )
        addTrackingArea(ta)
        trackingArea = ta
    }
    
    override func mouseEntered(with event: NSEvent) {
        // 用 set() 而不是 push()/pop()，避免栈失衡导致“越滚越错”
        cursor.set()
        super.mouseEntered(with: event)
    }
    
    override func mouseExited(with event: NSEvent) {
        NSCursor.arrow.set()
        super.mouseExited(with: event)
    }
    
    // 在层级变动时兜底重置
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { NSCursor.arrow.set() }
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


extension View {
    @ViewBuilder
    public func hoverCursor(
        _ style: CursorStyle,
        forceAppKit: Bool = false
    ) -> some View {
        if #available(macOS 15.0, *), !forceAppKit {
            // 15+ 优先使用指针样式（系统更稳），否则走 NSViewRepresentable
            self.pointerStyle(style.asPointerStyle())
        } else if #available(macOS 13.0, *) {
            modifier(HoverCursorModifier(cursor: style.asNSCursor))
        } else {
            self
        }
    }
}
#endif // canImport(AppKit)
