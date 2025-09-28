//
//  FlexibleSplitLayout.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 7/30/25.
//

import SwiftUI
import SFSafeSymbols

/// 定义分屏排布方案（最多支持 3 屏）
public enum SplitArrangement: Hashable {
    case single               // 单屏
    case horizontal           // 2 屏：左右
    case vertical             // 2 屏：上下
    case oneTopTwoBottom      // 3 屏：上 1 屏，下面 2 屏
    case twoTopOneBottom      // 3 屏：上 2 屏，下面 1 屏
    case oneLeftTwoRight      // 3 屏：左 1 屏，右 2 屏
    case twoLeftOneRight      // 3 屏：左 2 屏，右 1 屏
    
    
    static func cases(splitCount: Int) -> [SplitArrangement] {
        switch splitCount {
            case 1: return [.single]
            case 2: return [.horizontal, .vertical]
            case 3: return [.oneTopTwoBottom, .twoTopOneBottom, .oneLeftTwoRight, .twoLeftOneRight]
            default: return []
        }
    }
    
    @MainActor @ViewBuilder
    func iconView() -> some View {
        switch self {
            case .single:
                Image(systemSymbol: .rectangle)
            case .horizontal:
                Image(systemSymbol: .rectangleSplit2x1)
            case .vertical:
                Image(systemSymbol: .rectangleSplit1x2)
            case .oneTopTwoBottom:
                Image(systemSymbol: .questionmark)
            case .twoTopOneBottom:
                Image(systemSymbol: .questionmark)
            case .oneLeftTwoRight:
                Image(systemSymbol: .questionmark)
            case .twoLeftOneRight:
                Image(systemSymbol: .questionmark)
        }
    }
}

@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
public struct FlexibleSplitLayout: Layout {
    public let arrangement: SplitArrangement
    public let ratios: [CGFloat]
    public let spacing: CGFloat    // 子视图间隔 & divider 宽度

    public init(
        arrangement: SplitArrangement,
        ratios: [CGFloat] = [],
        spacing: CGFloat = 0
    ) {
        self.arrangement = arrangement
        self.ratios = ratios
        self.spacing = spacing
    }

    public func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout Void
    ) -> CGSize {
        proposal.replacingUnspecifiedDimensions()
    }

    public func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout Void
    ) {
        let count = subviews.count
        func eq(_ parts: Int) -> [CGFloat] {
            Array(repeating: 1.0 / CGFloat(parts), count: parts)
        }
        let r = ratios.isEmpty ? eq(count) : ratios
        let g = spacing

        switch (count, arrangement) {
        case (1, _):
            subviews[0].place(
                at: bounds.origin,
                proposal: .init(width: bounds.width, height: bounds.height)
            )

        case (2, .horizontal):
            let totalW = bounds.width - g
            let w1 = totalW * r[0]
            let w2 = totalW - w1
            subviews[0].place(
                at: bounds.origin,
                proposal: .init(width: w1, height: bounds.height)
            )
            subviews[1].place(
                at: CGPoint(x: bounds.minX + w1 + g, y: bounds.minY),
                proposal: .init(width: w2, height: bounds.height)
            )

        case (2, .vertical):
            let totalH = bounds.height - g
            let h1 = totalH * r[0]
            let h2 = totalH - h1
            subviews[0].place(
                at: bounds.origin,
                proposal: .init(width: bounds.width, height: h1)
            )
            subviews[1].place(
                at: CGPoint(x: bounds.minX, y: bounds.minY + h1 + g),
                proposal: .init(width: bounds.width, height: h2)
            )

        case (3, .oneTopTwoBottom):
            let totalH = bounds.height - g
            let topH   = totalH * r[0]
            let botH   = totalH - topH
            let y0     = bounds.minY + topH + g

            let totalW = bounds.width - g
            let w1     = totalW * r[1]
            let w2     = totalW - w1

            subviews[0].place(
                at: bounds.origin,
                proposal: .init(width: bounds.width, height: topH)
            )
            subviews[1].place(
                at: CGPoint(x: bounds.minX,         y: y0),
                proposal: .init(width: w1,          height: botH)
            )
            subviews[2].place(
                at: CGPoint(x: bounds.minX + w1 + g, y: y0),
                proposal: .init(width: w2,          height: botH)
            )

        case (3, .twoTopOneBottom):
            let totalH = bounds.height - g
            let topH   = totalH * r[0]
            let botH   = totalH - topH

            let totalW = bounds.width - g
            let w1     = totalW * r[1]
            let w2     = totalW - w1

            subviews[0].place(
                at: bounds.origin,
                proposal: .init(width: w1,      height: topH)
            )
            subviews[1].place(
                at: CGPoint(x: bounds.minX + w1 + g, y: bounds.minY),
                proposal: .init(width: w2,      height: topH)
            )
            subviews[2].place(
                at: CGPoint(x: bounds.minX,       y: bounds.minY + topH + g),
                proposal: .init(width: bounds.width, height: botH)
            )

        case (3, .oneLeftTwoRight):
            let totalW = bounds.width - g
            let leftW  = totalW * r[0]
            let rightW = totalW - leftW
            let x0     = bounds.minX + leftW + g

            let totalH = bounds.height - g
            let topH   = totalH * r[1]
            let botH   = totalH - topH

            subviews[0].place(
                at: bounds.origin,
                proposal: .init(width: leftW, height: bounds.height)
            )
            subviews[1].place(
                at: CGPoint(x: x0, y: bounds.minY),
                proposal: .init(width: rightW, height: topH)
            )
            subviews[2].place(
                at: CGPoint(x: x0, y: bounds.minY + topH + g),
                proposal: .init(width: rightW, height: botH)
            )

        case (3, .twoLeftOneRight):
            let totalW = bounds.width - g
            let leftW  = totalW * r[0]
            let rightW = totalW - leftW
            let x0     = bounds.minX + leftW + g

            let totalH = bounds.height - g
            let topH   = totalH * r[1]
            let botH   = totalH - topH

            subviews[0].place(
                at: bounds.origin,
                proposal: .init(width: leftW, height: topH)
            )
            subviews[1].place(
                at: CGPoint(x: bounds.minX, y: bounds.minY + topH + g),
                proposal: .init(width: leftW, height: botH)
            )
            subviews[2].place(
                at: CGPoint(x: x0, y: bounds.minY),
                proposal: .init(width: rightW, height: bounds.height)
            )

        default:
            // fallback equal grid
            let cols = min(2, count)
            let rows = (count + cols - 1) / cols
            let w    = (bounds.width - CGFloat(cols - 1) * g) / CGFloat(cols)
            let h    = (bounds.height - CGFloat(rows - 1) * g) / CGFloat(rows)
            for i in subviews.indices {
                let row = i / cols, col = i % cols
                let x = bounds.minX + CGFloat(col) * (w + g)
                let y = bounds.minY + CGFloat(row) * (h + g)
                subviews[i].place(
                    at: CGPoint(x: x, y: y),
                    proposal: .init(width: w, height: h)
                )
            }
        }
    }
}

