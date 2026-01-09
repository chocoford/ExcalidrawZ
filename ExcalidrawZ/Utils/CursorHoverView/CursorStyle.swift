//
//  HoverPointerStyle.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 8/19/25.
//

import SwiftUI
// MARK: - 基础方向类型（与 PointerStyle 的 directions 语义对齐）

/// 水平方向集合：列/竖向分割线的可调整方向
@frozen public struct HDir: OptionSet, Sendable, Hashable {
    public let rawValue: Int8
    @inlinable public init(rawValue: Int8) { self.rawValue = rawValue }

    public static let leading  = Self(rawValue: 1 << 0)
    public static let trailing = Self(rawValue: 1 << 1)
    public static let both: Self = [.leading, .trailing]
}

/// 垂直方向集合：行/横向分割线的可调整方向
@frozen public struct VDir: OptionSet, Sendable, Hashable {
    public let rawValue: Int8
    @inlinable public init(rawValue: Int8) { self.rawValue = rawValue }

    public static let up   = Self(rawValue: 1 << 0)
    public static let down = Self(rawValue: 1 << 1)
    public static let both: Self = [.up, .down]
}

/// 框选缩放方向集合：是否可向内/向外缩放，语义对应 SwiftUI.FrameResizeDirection.Set
@frozen public struct FrameResizeDir: OptionSet, Sendable, Hashable {
    public let rawValue: Int8
    @inlinable public init(rawValue: Int8) { self.rawValue = rawValue }

    /// 允许向内（缩小）调整
    public static let inward  = Self(rawValue: 1 << 0)
    /// 允许向外（放大）调整
    public static let outward = Self(rawValue: 1 << 1)
    /// 允许双向调整
    public static let all: Self = [.inward, .outward]
}

/// 框选缩放的“抓取点”位置，语义对应 SwiftUI.FrameResizePosition
@frozen public enum FrameResizePos: Int8, CaseIterable, Sendable {
    case top
    case bottom
    case leading
    case trailing
    case topLeading
    case topTrailing
    case bottomLeading
    case bottomTrailing
}

// MARK: - 统一指针样式抽象（能力面与 SwiftUI.PointerStyle 对齐）

@frozen public enum CursorStyle: Sendable, Equatable {
    /// 平台默认样式（macOS 为箭头）
    case `default`

    /// 水平文本插入/选择（I-beam 横向）
    case horizontalText
    /// 垂直文本插入/选择（I-beam 竖向）
    case verticalText

    /// 矩形/精确选区（十字准星）
    case rectSelection

    /// 可拖拽但未按下（张开手）
    case grabIdle
    /// 正在拖拽（握拳）
    case grabActive

    /// 链接/可点击（手指）
    case link

    /// 可放大（放大镜+）
    case zoomIn
    /// 可缩小（放大镜−）
    case zoomOut

    /// 列（竖向分割）尺寸调整
    case columnResize(directions: HDir)
    /// 行（横向分割）尺寸调整
    case rowResize(directions: VDir)

    /// 框选边/角尺寸调整
    case frameResize(position: FrameResizePos, directions: FrameResizeDir)
}
    
#if canImport(AppKit)
import AppKit

// MARK: - 映射到 SwiftUI.PointerStyle (macOS 15+)

@available(macOS 15.0, *)
extension CursorStyle {
    func asPointerStyle() -> PointerStyle {
        switch self {
            case .default:         return .default
            case .horizontalText:  return .horizontalText
            case .verticalText:    return .verticalText
            case .rectSelection:   return .rectSelection
            case .grabIdle:        return .grabIdle
            case .grabActive:      return .grabActive
            case .link:            return .link
            case .zoomIn:          return .zoomIn
            case .zoomOut:         return .zoomOut
                
            case .columnResize(let d):
                var dirs = HorizontalDirection.Set()
                if d.contains(.leading)  { dirs.insert(.leading) }
                if d.contains(.trailing) { dirs.insert(.trailing) }
                // 至少给一个，避免空集
                if dirs.isEmpty { dirs = [.leading, .trailing] }
                return .columnResize(directions: dirs)
                
            case .rowResize(let d):
                var dirs = VerticalDirection.Set()
                if d.contains(.up)   { dirs.insert(.up) }
                if d.contains(.down) { dirs.insert(.down) }
                if dirs.isEmpty { dirs = [.up, .down] }
                return .rowResize(directions: dirs)
                
            case .frameResize(let pos, let d):
                let p: FrameResizePosition = {
                    switch pos {
                        case .top:            return .top
                        case .bottom:         return .bottom
                        case .leading:        return .leading
                        case .trailing:       return .trailing
                        case .topLeading:     return .topLeading
                        case .topTrailing:    return .topTrailing
                        case .bottomLeading:  return .bottomLeading
                        case .bottomTrailing: return .bottomTrailing
                    }
                }()
                var dirs = FrameResizeDirection.Set()
                if d.contains(.inward) { dirs.insert(.inward) }
                if d.contains(.outward) { dirs.insert(.outward) }
                if dirs.isEmpty { dirs = .all }
                return .frameResize(position: p, directions: dirs)
        }
    }
}

// MARK: - 映射到 NSCursor (macOS 14 及以下)

extension CursorStyle {
    var asNSCursor: NSCursor {
        switch self {
            case .default:         return .arrow
            case .horizontalText:  return .iBeam
            case .verticalText:
                // 竖排 I-beam：能用就用，老系统回落到普通 I-beam
                let sel = NSSelectorFromString("IBeamCursorForVerticalLayout")
                if NSCursor.responds(to: sel),
                   let cur = (NSCursor.self as AnyObject).perform(sel)?.takeUnretainedValue() as? NSCursor {
                    return cur
                }
                return .iBeam
            case .rectSelection:   return .crosshair
            case .grabIdle:        return .openHand
            case .grabActive:      return .closedHand
            case .link:            return .pointingHand
            case .zoomIn, .zoomOut:
                // AppKit 没有放大镜指针，回退为 crosshair 或 arrow
                return .crosshair
                
            case .columnResize:
                // 任意水平方向 → 左右
                return .resizeLeftRight
                
            case .rowResize:
                // 任意垂直方向 → 上下
                return .resizeUpDown
                
            case .frameResize(let pos, _):
                // 边：按水平/垂直方向选左右或上下；角：选对角线
                switch pos {
                    case .leading, .trailing:
                        return .resizeLeftRight
                    case .top, .bottom:
                        return .resizeUpDown
                    case .topLeading, .bottomTrailing:
                        // ↘︎↖︎ 与 ↖︎↘︎ 的具体区分在 AppKit 里不可控，统一对角
                        if let diag = NSCursor.value(forKey: "resizeDiagonal") as? NSCursor {
                            return diag
                        }
                        return .resizeLeftRight // fallback
                    case .topTrailing, .bottomLeading:
                        if let diag = NSCursor.value(forKey: "resizeDiagonal") as? NSCursor {
                            return diag
                        }
                        return .resizeUpDown // fallback
                }
        }
    }
}

#endif // canImport(AppKit)
