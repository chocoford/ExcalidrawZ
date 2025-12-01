//
//  EdgeHoverView.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 7/30/25.
//

import SwiftUI
#if canImport(AppKit)
import AppKit

struct EdgeHoverView: NSViewRepresentable {
    /// 要监测的边
    let edge: Edge
    /// 区域占比 (0..<1)
    let percentage: CGFloat
    /// 回调：鼠标进入/离开该边区域
    let onHover: (Bool) -> Void
    
    func makeNSView(context: Context) -> TrackingView {
        let view = TrackingView()
        view.edge = edge
        view.percentage = percentage
        view.onHover = onHover
        return view
    }
    
    func updateNSView(_ nsView: TrackingView, context: Context) {
        nsView.edge = edge
        nsView.percentage = percentage
        nsView.onHover = onHover
        nsView.needsLayout = true
    }
    
    final class TrackingView: NSView {
        var edge: Edge = .top
        var percentage: CGFloat = 0.5
        var onHover: ((Bool) -> Void)?
        
        private var trackingArea: NSTrackingArea?
        
        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            if let old = trackingArea {
                removeTrackingArea(old)
            }
            
            // 计算要监测的区域
            let w = bounds.width
            let h = bounds.height
            let rect: NSRect
            switch edge {
                case .top:
                    rect = NSRect(x: 0,
                                  y: h * (1 - percentage),
                                  width: w,
                                  height: h * percentage)
                case .bottom:
                    rect = NSRect(x: 0,
                                  y: 0,
                                  width: w,
                                  height: h * percentage)
                case .leading:
                    rect = NSRect(x: 0,
                                  y: 0,
                                  width: w * percentage,
                                  height: h)
                case .trailing:
                    rect = NSRect(x: w * (1 - percentage),
                                  y: 0,
                                  width: w * percentage,
                                  height: h)
                    
            }
            
            trackingArea = NSTrackingArea(rect: rect,
                                          options: [.mouseEnteredAndExited, .activeAlways],
                                          owner: self,
                                          userInfo: nil)
            addTrackingArea(trackingArea!)
        }
        
        /// 不拦截任何事件，让它们都透传给下面的 SwiftUI 视图
        override func hitTest(_ point: NSPoint) -> NSView? {
            nil
        }
        
        override func mouseEntered(with event: NSEvent) {
            onHover?(true)
        }
        
        override func mouseExited(with event: NSEvent) {
            onHover?(false)
        }
    }
}
#endif
