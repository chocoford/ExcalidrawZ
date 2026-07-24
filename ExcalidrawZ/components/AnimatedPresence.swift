//
//  AnimatedPresence.swift
//  ExcalidrawZ
//
//  Adapted from fatbobman/AnimatedPresence.swift:
//  https://gist.github.com/fatbobman/02a6ffffd58f0997b9f9155b89fea490
//

import SwiftUI
import ChocofordUI

/// 行场景中替代 `VStack` 的窄 layout — 当某些 child 可能折叠到 0 高度时，把
/// **相邻 spacing 也按 presence progress 连续缩放**，使折叠的最后阶段不出现一次
/// 非动画化的 spacing 跳变。
///
/// ## 为什么不直接用 VStack
///
/// `VStack(spacing: x)` 的 spacing 是父容器对所有 child 的 unconditional 承诺：
/// 不论 child 当前高度是否为 0，相邻间距都硬性插入 `x`。当 child 折叠（高度
/// 动画到 0）完成时，它在父容器里仍占一个 slot，spacing 在最后一帧之前都是
/// 全量 `x`，视觉上会比 child 自身的高度晚一拍才"真正消失"。
///
/// ## 工作方式
///
/// 1. child 通过 `.ignoredWhenCollapsed()` 显式 opt-in，告诉本 layout
///    "我可能折叠到 0；折叠时把我前后的 spacing 也算上"。
/// 2. child 通过 `.collapsibleSpacingProgress(_:)` 把当前 presence 进度（0…1）
///    暴露成 layoutValue；该 modifier 本身 conform `Animatable`，让原本静态
///    的 layoutValue 间接获得 animatable 能力，进度变化逐帧驱动父 layout
///    重新计算 spacing。
/// 3. 本 layout 在每对相邻 child 之间取 `min(prevScale, nextScale) × baseSpacing`
///    作为有效 spacing，scale 越接近 0，spacing 越小。
///
/// 这样 spacing 与 child 高度走同一条动画 timeline，折叠完成的同一帧 spacing
/// 也归 0，两者完美同步，没有"高度先到 0、spacing 再消失"的二段感。
///
/// ## 设计边界
///
/// - 只覆盖 `.leading` / `.center` / `.trailing` 三类常见对齐。需要 `alignmentGuide`
///   定制时，请把那部分内容包在内部 `VStack` 里，由内层 `VStack` 处理对齐，本
///   layout 只负责 spacing 的 collapse-aware 行为。
/// - 不试图覆盖 `AnyLayout` 切换或 `VStackLayout` 兼容；那些场景继续用 SwiftUI 原生。
/// - 当 child 未标 `.ignoredWhenCollapsed()` 时，scale 恒为 1，行为退化为
///   普通 fixed-spacing VStack；本组件对非折叠场景没有副作用。
struct CollapsibleSpacingVStack: Layout {
    enum Alignment {
        case leading
        case center
        case trailing
    }

    var alignment: Alignment
    var spacing: CGFloat?

    /// 在没有 explicit `collapsibleSpacingProgress` 时的退路阈值：高度低于此值
    /// 视作折叠态。仅在 child 标了 `.ignoredWhenCollapsed()` 但没暴露 progress
    /// 的极端 case 生效；正常 AnimatedPresence 消费者总是 push progress，不会
    /// 落到该 binary 分支。
    private let collapsedThreshold: CGFloat = 0.5

    init(alignment: Alignment = .center, spacing: CGFloat? = nil) {
        self.alignment = alignment
        self.spacing = spacing
    }

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        let snapshot = currentSnapshot(subviews: subviews, width: proposal.width)

        // 完全折叠（scale == 0）的 child 不参与 width 累计：它的内容在父容器中
        // 应当视为"暂时不存在"。这是一个已知简化——若某个 row 唯一最宽的 child
        // 恰好折叠，父容器宽度会在折叠完成那一帧收窄；NoteSwitcherRow 这类
        // child 宽度大致一致的场景看不到该效应。
        let width = snapshot.reduce(into: CGFloat(0)) { partial, item in
            if item.scale > 0 {
                partial = max(partial, item.size.width)
            }
        }

        // height = Σ(item.size.height + item.spacingAfter)。spacingAfter 已在
        // currentSnapshot 内一次性算好（含 scale 缩放与 bridge 补偿），
        // placeSubviews 用同一份数据，两阶段不可能给出不同高度。
        let height = snapshot.reduce(into: CGFloat(0)) { partial, item in
            partial += item.size.height + item.spacingAfter
        }

        return CGSize(width: width, height: height)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        let snapshot = currentSnapshot(subviews: subviews, width: bounds.width)

        var y = bounds.minY
        for index in snapshot.indices {
            let item = snapshot[index]
            subviews[index].place(
                at: CGPoint(x: xOrigin(for: item.size, in: bounds), y: y),
                anchor: .topLeading,
                proposal: ProposedViewSize(width: bounds.width, height: item.size.height)
            )
            // 同样的 size.height + spacingAfter，与 sizeThatFits 的累加公式
            // 完全对称——sizeThatFits 报回的高度是 placeSubviews 推进 y 的
            // 终点，结构上不可能漂移。
            y += item.size.height + item.spacingAfter
        }
    }

    /// 一次性算出每个 child 的 `(size, scale, spacingAfter)` 快照，让
    /// `sizeThatFits` 与 `placeSubviews` 共享同一组数值。
    ///
    /// `spacingAfter` 把"该 child 与下一 child 之间的 spacing"挂到 child 自身：
    /// 两个 layout method 都用 `size.height + spacingAfter` 累加，公式对称，
    /// 物理上不可能给出不同的高度。最后一个 child 的 spacingAfter = 0。
    ///
    /// 处理分两步：先按相邻 pair 的 scale 缩 base spacing；再调用
    /// `addBridgeSpacings` 给被折叠 child 隔开的 visible sibling 之间补回 base
    /// spacing。两步合起来才能覆盖完整的语义。
    ///
    /// **本 layout 不实现 application-level cache**：
    ///
    /// - child 内部 state 变化（例如 `AnimatedPresence.visibleHeight` 在动画
    ///   transaction 内逐帧变化）会改变 child 报回的 intrinsic，但 SwiftUI
    ///   只在 subview list 增删 / 顺序变化时调用 `updateCache`——没有合适
    ///   signal 让我们让按 width 缓存的 sizes 失效。一旦 cache 命中但 child
    ///   intrinsic 已变，外层就会按旧高度推进 `y`，下一个 child 与当前
    ///   child 的渲染区域发生重叠。
    /// - `subview.sizeThatFits` 在 SwiftUI 框架内部已经有 measurement 缓存，
    ///   重复调用同一 proposal 不会真的重测底层 view tree intrinsic。应用层
    ///   再 cache 一层既不安全也无明显收益。
    private func currentSnapshot(
        subviews: Subviews,
        width: CGFloat?
    ) -> [Item] {
        let sizes = subviews.map { subview in
            sanitized(subview.sizeThatFits(ProposedViewSize(width: width, height: nil)))
        }
        let scales = subviews.indices.map { index in
            spacingScale(
                forHeight: sizes[index].height,
                isCollapsible: subviews[index][CollapsedIgnorableKey.self],
                progress: subviews[index][CollapsibleSpacingProgressKey.self]
            )
        }

        var spacingAfterValues = subviews.indices.map { index in
            let nextIndex = subviews.index(after: index)
            return nextIndex < subviews.endIndex
                ? scaledSpacingDistance(
                    previous: subviews[index],
                    next: subviews[nextIndex],
                    previousScale: scales[index],
                    nextScale: scales[nextIndex]
                )
                : 0
        }
        addBridgeSpacings(
            to: &spacingAfterValues,
            subviews: subviews,
            scales: scales
        )

        return subviews.indices.map { index in
            Item(
                size: sizes[index],
                scale: scales[index],
                spacingAfter: spacingAfterValues[index]
            )
        }
    }

    /// 给被折叠 child 隔开的两个 visible sibling 之间补一份 bridge spacing。
    ///
    /// `scaledSpacingDistance` 用 `min(prev, next)` 缩放 base spacing 在
    /// `visible / collapsed / visible` 模式下过激：collapsed child 的两侧
    /// spacing 都被压成 0，让前后两个 visible sibling 完全贴合。但折叠完成
    /// 后，prevVisible 与 nextVisible 实际是新的相邻 sibling，应当享有正常
    /// 的 base spacing。
    ///
    /// bridge 公式：
    /// - 对每段连续 collapsed run `[runStart, runEnd]`，
    /// - 若 run 前后都有 visible sibling，取
    ///   `baseSpacingDistance(prevVisible, nextVisible) × (1 - maxRunScale)`，
    /// - **均分到 prevVisible 与 runEnd 两侧**——让 collapse 中间态左右
    ///   spacing 分布对称，AP 在 expand 过程中视觉上"从中间长开"而非偏向
    ///   某一侧。
    ///
    /// `1 - maxRunScale` 让 bridge 与 collapse 进度同步插值。`maxRunScale`
    /// 而非 `minRunScale`：run 内任一 child 仍较 visible（scale 较大）时，
    /// run 作为视觉中断仍存在，bridge 弱化。
    private func addBridgeSpacings(
        to spacingAfterValues: inout [CGFloat],
        subviews: Subviews,
        scales: [CGFloat]
    ) {
        var index = subviews.startIndex
        while index < subviews.endIndex {
            guard scales[index] < 1 else {
                index = subviews.index(after: index)
                continue
            }

            // 扩展 collapsed run [runStart, runEnd]
            let runStart = index
            var runEnd = index
            var maxRunScale = scales[index]
            var nextIndex = subviews.index(after: index)
            while nextIndex < subviews.endIndex, scales[nextIndex] < 1 {
                runEnd = nextIndex
                maxRunScale = max(maxRunScale, scales[nextIndex])
                nextIndex = subviews.index(after: nextIndex)
            }

            // 只在 run 前后都有 visible sibling 时补 bridge。
            // 端点处的 collapsed run（run 在最前或最后）没有"新相邻对"需要
            // 桥接，正常用 scale 缩 spacing 就够了。
            if runStart > subviews.startIndex, nextIndex < subviews.endIndex {
                let previousVisible = subviews.index(before: runStart)
                let bridgeProgress = 1 - maxRunScale
                let halfBridge =
                    baseSpacingDistance(
                        previous: subviews[previousVisible],
                        next: subviews[nextIndex]
                    ) * bridgeProgress / 2
                spacingAfterValues[previousVisible] += halfBridge
                spacingAfterValues[runEnd] += halfBridge
            }

            index = nextIndex
        }
    }

    /// 应用 scale 后的相邻 spacing。base spacing × min(prevScale, nextScale)。
    ///
    /// 任一侧 collapse 都按比例收缩 spacing，是"高度与 spacing 同步收敛"的核心。
    /// `visible / collapsed / visible` 模式下两侧 spacing 都被压成 0，由
    /// `addBridgeSpacings` 在外层补偿。
    private func scaledSpacingDistance(
        previous: LayoutSubview,
        next: LayoutSubview,
        previousScale: CGFloat,
        nextScale: CGFloat
    ) -> CGFloat {
        baseSpacingDistance(previous: previous, next: next)
            * min(previousScale, nextScale)
    }

    /// 不考虑 scale 的 base spacing。explicit `spacing` 优先；否则回退到
    /// SwiftUI 默认的 `ViewSpacing.distance(to:along:)`，让相邻 child 的
    /// spacing 偏好共同决定。本函数返回的是 bridge 计算与 `scaledSpacingDistance`
    /// 共用的"原始距离"。
    private func baseSpacingDistance(
        previous: LayoutSubview,
        next: LayoutSubview
    ) -> CGFloat {
        let distance =
            spacing
            ?? previous.spacing.distance(
                to: next.spacing,
                along: .vertical
            )
        guard distance.isFinite else { return 0 }
        return max(0, distance)
    }

    /// 把"是否折叠"映射成 0…1 的连续 scale。
    ///
    /// - 未 opt-in 的 child：scale 恒为 1，spacing 不缩放（行为退化为普通 VStack）。
    /// - opt-in 且 child 暴露 progress：直接采用 progress，让 spacing 与 presence
    ///   动画同步插值——这是 AnimatedPresence 走的主路径。
    /// - opt-in 但没暴露 progress：用高度阈值做 binary fallback，避免 layoutValue
    ///   合约不完整时 spacing 永远不收缩。
    private func spacingScale(
        forHeight height: CGFloat,
        isCollapsible: Bool,
        progress: CGFloat?
    ) -> CGFloat {
        guard isCollapsible else { return 1 }
        if let progress, progress.isFinite {
            return min(1, max(0, progress))
        }
        return height > collapsedThreshold ? 1 : 0
    }

    private func sanitized(_ size: CGSize) -> CGSize {
        CGSize(
            width: size.width.isFinite ? max(0, size.width) : 0,
            height: size.height.isFinite ? max(0, size.height) : 0
        )
    }

    private func xOrigin(for size: CGSize, in bounds: CGRect) -> CGFloat {
        switch alignment {
        case .trailing:
            return bounds.maxX - size.width
        case .center:
            return bounds.midX - size.width / 2
        case .leading:
            return bounds.minX
        }
    }

    private struct Item {
        let size: CGSize
        let scale: CGFloat
        /// 该 child 与下一 child 之间的 spacing；最后一个 child 为 0。
        /// 已含 scale 缩放与 bridge 补偿。让 sizeThatFits 与 placeSubviews
        /// 共用同一组数值，公式 `size.height + spacingAfter` 在两个 method
        /// 中对称，物理上不可能不一致。
        let spacingAfter: CGFloat
    }
}

/// 标记 child 在自身折叠到 0 高度时，可以被父 layout 视作"在 spacing 计算里
/// 不存在"。只有 `CollapsibleSpacingVStack` 等显式读这个 key 的 layout 会
/// 消费它；标准 `VStack` 不读 layoutValue，对它无副作用。
private struct CollapsedIgnorableKey: LayoutValueKey {
    nonisolated static let defaultValue = false
}

/// child 把自身的 presence 进度（0 = collapsed，1 = expanded）通过这个 key
/// 暴露给父 layout。值由 `CollapsibleSpacingProgressModifier` 写入；后者
/// conform `Animatable`，使原本不可 animate 的 layoutValue 间接获得逐帧
/// 插值能力。
private struct CollapsibleSpacingProgressKey: LayoutValueKey {
    nonisolated static let defaultValue: CGFloat? = nil
}

/// 关键技巧：用 ViewModifier+Animatable 把 LayoutValueKey 变成 animatable 通道。
///
/// LayoutValueKey 本身是 layout 期读取的静态属性，不能直接被 SwiftUI 动画系统
/// 插值。但 ViewModifier 可以 conform `Animatable`：在 `withAnimation` transaction
/// 内，SwiftUI 逐帧把 `animatableData` 插值后调用 `body`，每帧的 `layoutValue`
/// 写入的就是当前帧的 progress。父 layout 在每次 layout pass 读 layoutValue，
/// 得到的便是逐帧插值后的值。
///
/// 这条路径让我们能把 spacing 的 collapse 与 height 的 collapse 锁在同一个
/// `withAnimation` transaction 内，两条 timeline 共享 curve 与 duration，
/// 自然同步。
private struct CollapsibleSpacingProgressModifier: ViewModifier, Animatable {
    var progress: CGFloat

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func body(content: Content) -> some View {
        content.layoutValue(
            key: CollapsibleSpacingProgressKey.self,
            value: min(1, max(0, progress))
        )
    }
}

extension View {
    /// 让该 view 在自身折叠到 0 高度时被 `CollapsibleSpacingVStack` 在 spacing
    /// 计算中视为缺席。对不消费 `CollapsedIgnorableKey` 的父容器无副作用。
    func ignoredWhenCollapsed(_ enabled: Bool = true) -> some View {
        layoutValue(key: CollapsedIgnorableKey.self, value: enabled)
    }

    /// 把 0…1 的 presence 进度通过 layoutValue 暴露给父 `CollapsibleSpacingVStack`。
    /// 通常由 `AnimatedPresence` 等自身管理 collapse 动画的组件内部调用；
    /// 普通调用方不需要直接接触该 API。
    func collapsibleSpacingProgress(_ progress: CGFloat) -> some View {
        modifier(CollapsibleSpacingProgressModifier(progress: progress))
    }
}

enum AnimatedPresenceContentTransition {
    case clipped
    case fadeWithContainer
    case deferredOpacity
}

/// 为行内 optional 数据提供"出现 / 消失 / 内容尺寸变化"的连续高度过渡。
///
/// ## 整体机制
///
/// 组件由三条同步的 timeline 协同：
///
/// 1. **content timeline** — `displayValue` 与外部 `value` 解耦。`value` 在外部
///    随时可能被数据同步流改写；`displayValue` 是组件内部为渲染保留的 retained
///    copy，只在合适的时机切换（出现 / 改写时立即，消失时延迟到折叠完成）。
///    这是"消失动画拥有渲染素材"的关键。
///
/// 2. **height timeline** — `visibleHeight` 是 push-based animatable state，
///    由自定义 `VisibleHeightLayout` 作为 `animatableData` 暴露给 SwiftUI。
///    content 的真实 intrinsic height 通过 `background { GeometryReader }`
///    + 私有 preference 推送到 `handleMeasurement`，再由 `withAnimation`
///    驱动 `visibleHeight` 到新 target。`nil <-> value` 与 `value -> newValue`
///    走同一条插值通道，不依赖 SwiftUI 的 implicit layout animation。
///
/// 3. **spacing timeline** — `spacingProgress` 与 `visibleHeight` 同步更新：
///    首次 settle 直接赋值，后续变化在同一个 `withAnimation` block 内更新。
///    进度通过 `.collapsibleSpacingProgress(_:)` 暴露给父
///    `CollapsibleSpacingVStack`。父 layout 据此连续缩放相邻 spacing，使折叠到
///    0 的瞬间 spacing 也恰好归 0，没有"高度先到 0、spacing 再消失"的二段感。
///
/// ## 关键 invariants
///
/// - `visibleHeight` 与 `spacingProgress` 同生同灭：要么都立即赋值（首次 settle），
///   要么都在同一个 transaction 内动画。任何只更新其一的代码路径都会破坏同步。
/// - `displayValue` 在折叠期间保留 last visible payload，直到 collapse completion
///   才清空；`collapseToken` 防止旧 completion 误清新提交的值。
/// - `handleMeasurement` 用 `targetHeight`（最近一次"想到达的高度"）而非
///   `visibleHeight`（当前插值中间值）作为去重 key——动画期间 `visibleHeight`
///   每帧都不同，与它比较会让每一帧 measurement 看起来都是"新目标"，触发
///   measurement feedback loop。
struct AnimatedPresence<Value: Equatable, Content: View>: View {
    private let value: Value?
    private let animation: Animation?
    private let contentAnimation: Animation
    private let swiftUIContentTransition: ContentTransition
    private let legacyContentTransition: AnimatedPresenceContentTransition?
    private let contentTransitionDelay: Duration
    private let removalAnimation: Animation?
    private let removalDelay: Duration?
    private let content: (Value) -> Content

    /// 渲染层使用的 retained payload。外部 `value` 在动画中途可能被同步流改写
    /// 或清空，`displayValue` 由组件状态机控制，保证折叠动画始终有素材可渲染。
    @State private var displayValue: Value?
    /// Layout 外部尺寸的 animatable state。由 `withAnimation` 驱动，配合
    /// `VisibleHeightLayout.animatableData` 让外部高度逐帧插值。
    @State private var visibleHeight: CGFloat = 0
    /// 最近一次有效 intrinsic height，用于旧版 `.fadeWithContainer` 的 opacity
    /// progress。折叠期间不能清零，否则 progress 会瞬间归 0。
    @State private var measuredHeight: CGFloat = 0
    /// 最近一次 measurement push 来的目标 intrinsic height，用作 `handleMeasurement`
    /// 内的去重锚点。注释里反复强调"与 target 比较而非与 visibleHeight 比较"
    /// 就是为了避开 measurement feedback loop。
    @State private var targetHeight: CGFloat = 0
    /// presence 进度（0 = 完全折叠，1 = 完全展开）。通过
    /// `.collapsibleSpacingProgress(_:)` 暴露给父 layout，让相邻 spacing
    /// 与高度同步缩放。**必须与 `visibleHeight` 同步更新；动画路径要在同一
    /// `withAnimation` 内更新**。
    @State private var spacingProgress: CGFloat = 0
    /// 旧版 `.deferredOpacity` 的独立内容透明度 timeline。
    @State private var contentOpacity: CGFloat = 0
    /// 组件 mount 时已有 value 的一次性标记：第一次 measurement 应直接 settle 到
    /// 自然高度，不做"展开"动画——否则 row 每次滚入屏幕都会重新出场，违反直觉。
    @State private var awaitingInitialMeasurement = false
    /// 折叠 completion 防腐 token。每次 value 变更都 +1；completion 内核对
    /// token 是否仍是自己启动时的值，避免"折叠中途 value 又回来了"那个旧
    /// completion 把新提交的 displayValue 错误清空。
    @State private var collapseToken = 0
    @State private var contentTransitionTask: Task<Void, Never>?
    @State private var removalTask: Task<Void, Never>?

    private var progress: CGFloat {
        measuredHeight > 0 ? min(max(visibleHeight / measuredHeight, 0), 1) : 0
    }

    private var renderedContentOpacity: CGFloat {
        switch legacyContentTransition {
        case .clipped:
            return 1
        case .fadeWithContainer:
            return progress
        case .deferredOpacity:
            return contentOpacity
        case nil:
            return 1
        }
    }

    private var clipsToVisibleBounds: Bool {
        switch legacyContentTransition {
        case .clipped, nil:
            return true
        case .fadeWithContainer, .deferredOpacity:
            return false
        }
    }

    init(
        value: Value?,
        animation: Animation? = .easeInOut(duration: 0.22),
        contentTransition: ContentTransition = .identity,
        removalAnimation: Animation? = nil,
        removalDelay: Duration? = .milliseconds(240),
        @ViewBuilder content: @escaping (Value) -> Content
    ) {
        self.value = value
        self.animation = animation
        self.contentAnimation = .easeInOut(duration: 0.16)
        self.swiftUIContentTransition = contentTransition
        self.legacyContentTransition = nil
        self.contentTransitionDelay = .milliseconds(140)
        self.removalAnimation = removalAnimation
        self.removalDelay = removalDelay
        self.content = content
    }

    init(
        value: Value?,
        animation: Animation = .easeInOut(duration: 0.22),
        contentAnimation: Animation = .easeInOut(duration: 0.16),
        contentTransition: AnimatedPresenceContentTransition = .fadeWithContainer,
        contentTransitionDelay: Duration = .milliseconds(140),
        removalAnimation: Animation? = nil,
        removalDelay: Duration = .milliseconds(240),
        @ViewBuilder content: @escaping (Value) -> Content
    ) {
        self.value = value
        self.animation = animation
        self.contentAnimation = contentAnimation
        self.swiftUIContentTransition = .identity
        self.legacyContentTransition = contentTransition
        self.contentTransitionDelay = contentTransitionDelay
        self.removalAnimation = removalAnimation
        self.removalDelay = removalDelay
        self.content = content
    }

    var body: some View {
        // VisibleHeightLayout 接管外部尺寸合约：layout output 是 visibleHeight，
        // content 在 layout 内部按 intrinsic 渲染，外层 .clipped() 截断溢出。
        // 折叠是"切"而非"压"，content 不变形，background measurement 也持续
        // 给出稳定 intrinsic。
        VisibleHeightLayout(visibleHeight: visibleHeight) {
            if let displayValue {
                content(displayValue)
                    // .fixedSize 让 content 在垂直方向锁定到 intrinsic 高度；
                    // 这条 modifier 与 background GeometryReader 是绑定关系：
                    // 后者读到的就是这个 intrinsic 尺寸。调用方在组件外再套
                    // .frame(height:) 或 .fixedSize(vertical:) 会破坏测量链路。
                    .fixedSize(horizontal: false, vertical: true)
                    .contentTransition(swiftUIContentTransition)
                    .animation(animation, value: displayValue)
                    .opacity(renderedContentOpacity)
                    .background {
                        // measurement push 通道：background 跟随 .fixedSize 后
                        // 的 intrinsic 几何；displayValue 切到不同尺寸时，
                        // GeometryReader 读到的 size.height 立即变化，preference
                        // 把新值推给 handleMeasurement，后者驱动 withAnimation。
                        GeometryReader { proxy in
                            Color.clear.preference(
                                key: AnimatedPresenceHeightKey.self,
                                value: proxy.size.height
                            )
                        }
                    }
            }
        }
        .modifier(AnimatedPresenceClipModifier(isClipped: clipsToVisibleBounds))
        .allowsHitTesting(value != nil && progress > 0.95)
        .onAppear { handleAppearance() }
        .watch(value: value) { newValue in handleValueChange(newValue) }
        .onPreferenceChange(AnimatedPresenceHeightKey.self) { measured in
            handleMeasurement(measured)
        }
        .onDisappear {
            contentTransitionTask?.cancel()
            removalTask?.cancel()
        }
        // 把 spacingProgress 通过 ViewModifier+Animatable 写入 layoutValue，
        // 让原本不可 animate 的 LayoutValueKey 间接获得逐帧插值能力。父
        // CollapsibleSpacingVStack 据此把相邻 spacing 与高度同步缩放；
        // 详见 CollapsibleSpacingProgressModifier 的注释。
        .collapsibleSpacingProgress(spacingProgress)
    }

    /// 处理组件 mount。
    ///
    /// 唯一职责是处理"mount 时就已经有 value"的情况：把 displayValue 同步到
    /// value，并打开 awaitingInitialMeasurement，让随后到来的第一次 measurement
    /// 直接 settle（而不是从 0 "展开"）。否则 row 每次滚入屏幕都会重新出场。
    ///
    /// 如果 mount 时 value 是 nil 则什么都不做：displayValue 默认就是 nil，
    /// 状态机停在 collapsed 起点，等待 onChange 驱动。
    private func handleAppearance() {
        if let value, displayValue == nil {
            displayValue = value
            prepareContentForInsertion()
            awaitingInitialMeasurement = true
        }
    }

    /// 处理外部 value 变化 — 三条 timeline 协同的入口。
    ///
    /// - `nil -> value` / `value -> newValue`：立即提交新 displayValue。随后
    ///   到达的 measurement 会驱动 visibleHeight 与 spacingProgress 动画到新
    ///   目标。`collapseToken += 1` 让任何尚未触发的旧 collapse completion
    ///   作废（场景：折叠途中 value 又回来了）。awaitingInitialMeasurement
    ///   显式归位，保证运行时变化总走动画路径，即便发生在 onAppear 之后立刻。
    ///
    /// - `value -> nil`：启动折叠。visibleHeight 与 spacingProgress 同时归 0，
    ///   动画完成后才把 displayValue 清空——"消失动画拥有渲染素材"靠这一步
    ///   实现。completion 内核对 collapseToken 与当前 value 状态，防止动画
    ///   途中 value 又被改写的场景里旧路径错误清掉新值。
    ///
    /// targetHeight 在折叠分支显式归 0：保证下一次出现时 measurement 与
    /// targetHeight 的差值必然 > 0.5，能正确触发新动画而不是被去重 guard 拦下。
    private func handleValueChange(_ newValue: Value?) {
        contentTransitionTask?.cancel()
        removalTask?.cancel()

        if let newValue {
            awaitingInitialMeasurement = false
            displayValue = newValue
            collapseToken += 1
            prepareContentForInsertion()
            if measuredHeight > 0 {
                withAnimation(animation) {
                    visibleHeight = measuredHeight
                    spacingProgress = 1
                }
                scheduleDeferredContentAppearanceIfNeeded()
            }
        } else {
            let token = collapseToken + 1
            collapseToken = token

            if legacyContentTransition == .deferredOpacity {
                withAnimation(contentAnimation) {
                    contentOpacity = 0
                }

                contentTransitionTask = Task { @MainActor in
                    try? await Task.sleep(for: contentTransitionDelay)
                    guard !Task.isCancelled, collapseToken == token, value == nil else { return }
                    collapseContainerAndScheduleRemoval(token: token)
                }
            } else {
                collapseContainerAndScheduleRemoval(token: token)
            }
        }
    }

    private func prepareContentForInsertion() {
        switch legacyContentTransition {
        case .clipped, .fadeWithContainer, nil:
            contentOpacity = 1
        case .deferredOpacity:
            contentOpacity = 0
        }
    }

    private func scheduleDeferredContentAppearanceIfNeeded() {
        guard legacyContentTransition == .deferredOpacity,
              value != nil,
              displayValue != nil,
              measuredHeight > 0 else {
            return
        }

        contentTransitionTask?.cancel()
        contentTransitionTask = Task { @MainActor in
            try? await Task.sleep(for: contentTransitionDelay)
            guard !Task.isCancelled, value != nil else { return }
            withAnimation(contentAnimation) {
                contentOpacity = 1
            }
        }
    }

    private func collapseContainerAndScheduleRemoval(token: Int) {
        targetHeight = 0
        let collapseAnimation = removalAnimation ?? animation

        guard let removalDelay else {
            if #available(macOS 14.0, iOS 17.0, *) {
                withAnimation(collapseAnimation, completionCriteria: .logicallyComplete) {
                    visibleHeight = 0
                    spacingProgress = 0
                } completion: {
                    clearDisplayValueIfStillCollapsed(token: token)
                }
            } else {
                withAnimation(collapseAnimation) {
                    visibleHeight = 0
                    spacingProgress = 0
                }
                scheduleDisplayValueRemoval(token: token, delay: .milliseconds(240))
            }
            return
        }

        withAnimation(collapseAnimation) {
            visibleHeight = 0
            spacingProgress = 0
        }
        scheduleDisplayValueRemoval(token: token, delay: removalDelay)
    }

    private func scheduleDisplayValueRemoval(token: Int, delay: Duration) {
        removalTask?.cancel()
        removalTask = Task { @MainActor in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            clearDisplayValueIfStillCollapsed(token: token)
        }
    }

    private func clearDisplayValueIfStillCollapsed(token: Int) {
        guard collapseToken == token, value == nil else { return }
        displayValue = nil
        measuredHeight = 0
        targetHeight = 0
        contentOpacity = 0
    }

    /// 接收 background `GeometryReader` push 上来的 intrinsic height，驱动
    /// visibleHeight 与 spacingProgress 进入新动画。
    ///
    /// 三道 guard 各有作用：
    ///
    /// 1. `measured.isFinite` 过滤 NaN / Inf——SwiftUI 在某些 layout 过渡帧
    ///    可能短暂返回非有限值，需避免污染动画目标。
    /// 2. `displayValue != nil`：subview 不存在时不会有 measurement；但
    ///    onPreferenceChange 在内容消失瞬间还会触发一次默认值，需 ignore。
    /// 3. `value != nil`：折叠动画进行中，handleValueChange 已经把 visibleHeight
    ///    推向 0。此时 measurement 仍按 displayValue 报真实 intrinsic（折叠
    ///    期间 displayValue 还在），不应再把 visibleHeight 拉回去。
    ///
    /// `targetHeight` 而非 `visibleHeight` 作为去重锚点：动画途中 visibleHeight
    /// 是插值中间值，与它比较会让每一帧 measurement 看起来都是"新目标"，
    /// 触发新的 withAnimation，最终引发 measurement feedback loop。targetHeight
    /// 只在我们真正"想到达新值"时更新，是稳定锚点。
    ///
    /// 两条 state（visibleHeight、spacingProgress）必须同步更新：首次 settle
    /// 直接到位，动画路径则放在同一个 withAnimation 内，共用同一条 animation
    /// curve / duration，自然同步——这是类型顶部 invariants 强调的关键约束。
    private func handleMeasurement(_ measured: CGFloat) {
        guard
            measured.isFinite,
            displayValue != nil
        else { return }
        guard value != nil else { return }
        guard abs(measured - targetHeight) > 0.5 else { return }
        measuredHeight = measured
        targetHeight = measured

        if awaitingInitialMeasurement {
            // 首次 settle：两条 state 都直接到位，不走 withAnimation。避免
            // row 出现的瞬间播放一次"展开"动画。
            awaitingInitialMeasurement = false
            visibleHeight = measured
            spacingProgress = 1
            scheduleDeferredContentAppearanceIfNeeded()
        } else {
            withAnimation(animation) {
                visibleHeight = measured
                spacingProgress = 1
            }
            scheduleDeferredContentAppearanceIfNeeded()
        }
    }
}

private struct AnimatedPresenceClipModifier: ViewModifier {
    let isClipped: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if isClipped {
            content.clipped()
        } else {
            content
        }
    }
}

/// AnimatedPresence 的内层 Layout — 把 visibleHeight 作为 animatable 外部尺寸，
/// 但**不**约束 subview 的渲染尺寸。
///
/// 关键拆解：
///
/// - `sizeThatFits` 报给父容器 `(intrinsic.width, visibleHeight)`：外部看到
///   的是 layout 当前希望占据的高度，由 SwiftUI 通过 animatableData 逐帧驱动。
/// - `placeSubviews` 用 **intrinsic 高度**作为 proposal 把 subview 摆下去：
///   subview 按自然尺寸渲染，不被 visibleHeight 反向压缩。两条尺寸（外部
///   高度 vs subview 高度）的差额由 AnimatedPresence 外层的 `.clipped()`
///   承担——把溢出 visibleHeight 的部分裁掉。
///
/// 这条策略让折叠在视觉上是"自下而上揭示 / 截断"而非"内容塌陷"，且 subview
/// 的 intrinsic 在动画期间保持稳定，让 background GeometryReader 给出的
/// measurement 不会因为 layout 高度变化而被污染。
private struct VisibleHeightLayout: Layout {
    var visibleHeight: CGFloat

    /// 把 visibleHeight 暴露为 animatableData：在 `withAnimation` transaction
    /// 内 SwiftUI 逐帧调用 sizeThatFits + placeSubviews，每帧 visibleHeight
    /// 都是新插值——这是 height 平滑过渡的底层机制。
    var animatableData: CGFloat {
        get { visibleHeight }
        set { visibleHeight = newValue }
    }

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        guard let subview = subviews.first else { return .zero }
        // 询问 subview 在 unconstrained height 下的真实 intrinsic；不能把
        // proposal.height 传下去，否则 subview 会跟随当前折叠中的 visibleHeight
        // 压缩，导致测量与渲染都失真。
        let intrinsic = subview.sizeThatFits(
            ProposedViewSize(width: proposal.width, height: nil)
        )
        return CGSize(
            width: intrinsic.width.isFinite ? intrinsic.width : 0,
            // visibleHeight 在动画途中可能短暂出现极小负值（spring curve 的
            // overshoot），用 max(0, ...) 兜底保证不给父容器一个负尺寸。
            height: max(0, visibleHeight)
        )
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        guard let subview = subviews.first else { return }
        let intrinsic = subview.sizeThatFits(
            ProposedViewSize(width: bounds.width, height: nil)
        )
        // 用 intrinsic 提议 place：subview 按自然尺寸渲染。外层 .clipped()
        // 用 layout output（= visibleHeight）截断超出部分。折叠期间 subview
        // 内部并未被压缩，content 不变形，background measurement 持续给出
        // 稳定 intrinsic（关键：测量不被折叠中的可见区域污染）。
        subview.place(
            at: bounds.origin,
            anchor: .topLeading,
            proposal: ProposedViewSize(width: intrinsic.width, height: intrinsic.height)
        )
    }

    /// 不在这里把 spacing 强制设为 `.zero` 来消除父 implicit spacing。
    ///
    /// 理由：`ViewSpacing` 自身不是 animatable，binary 切换会在 visibleHeight
    /// 越过阈值的那一帧让 spacing 突变（hard jump），违反"高度与 spacing 同步
    /// 收敛"的设计目标。spacing 的连续控制应由父 layout 通过 progress 通道
    /// 处理——参见 `CollapsibleSpacingVStack` + `collapsibleSpacingProgress`。
    ///
    /// 这里返回 subview 自身的 spacing，让本 layout 作为 subview 出现时
    /// 透明地传递 child 的 spacing 偏好。
    func spacing(subviews: Subviews, cache: inout ()) -> ViewSpacing {
        subviews.first?.spacing ?? .zero
    }
}

/// content 通过 background `GeometryReader` 把自身 intrinsic height 推送到
/// 状态机的私有 channel。`fileprivate` 隔离保证不会被组件外的代码读到，
/// 避免被当成通用 frame measurement API 扩散——issue 176 明确约束了这一点。
///
/// `reduce` 取 max 保持旧版 AnimatedPresence 语义：SwiftUI 在复杂内容树中可能
/// 同轮推送默认 0 和真实测量值，不能让后到的 0 覆盖掉有效高度。
private struct AnimatedPresenceHeightKey: PreferenceKey {
    static var defaultValue: CGFloat { 0 }
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

#if DEBUG

    private struct AnimatedPresencePreviewRow: View {
        let title: String
        let detail: String?
        let animation: Animation

        init(
            title: String,
            detail: String?,
            animation: Animation = .smooth
        ) {
            self.title = title
            self.detail = detail
            self.animation = animation
        }

        var body: some View {
            CollapsibleSpacingVStack(alignment: .leading, spacing: 4) {
                Text(verbatim: title)
                    .lineLimit(1)
                    .font(.headline)

                AnimatedPresence(
                    value: detail,
                    animation: animation,
                    contentTransition: .opacity
                ) { detail in
                    Text(verbatim: detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }
                .ignoredWhenCollapsed()

                Text("Footer")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private struct AnimatedPresencePreview: View {
        @State private var isVisible = true
        @State private var sampleIndex = 0

        private let samples = [
            "Short change.",
            "A much longer change that wraps across several lines and forces the row to recalculate its height without the explicit visible-height channel.",
            "Medium change that still uses the same plain Text lifecycle.",
        ]

        var body: some View {
            List {
                AnimatedPresencePreviewRow(
                    title: "Smooth motion timing",
                    detail: isVisible ? samples[sampleIndex] : nil,
                    animation: .smooth
                )

                Button(isVisible ? "Hide" : "Show") {
                    isVisible.toggle()
                }

                Button("Next value") {
                    isVisible = true
                    sampleIndex = (sampleIndex + 1) % samples.count
                }
            }
        }
    }

    private struct SwiftUINativeHeightChangePreview: View {
        @State private var isVisible = true
        @State private var sampleIndex = 0

        private let optionalDetail =
            "Native SwiftUI removes and inserts this payload directly. In List, row height tends to update as a discrete layout change."
        private let samples = [
            "Short native change.",
            "A much longer native change that wraps across several lines and forces the row to recalculate its height without the explicit visible-height channel.",
            "Medium native change that still uses the same plain Text lifecycle.",
        ]

        var body: some View {
            List {
                VStack(alignment: .leading) {
                    Text("Native on/off")
                        .lineLimit(1)
                        .font(.headline)

                    if isVisible {
                        Text(verbatim: optionalDetail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                            .transition(.opacity)
                    }


                    Text("Footer")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .leading) {
                    Text("Native Change")
                        .lineLimit(1)
                        .font(.headline)

                    Text(verbatim: samples[sampleIndex])
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                        .contentTransition(.opacity)
                        .animation(.smooth, value: sampleIndex)

                    Text("Footer")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Button(isVisible ? "Hide" : "Show") {
                    withAnimation(.smooth) {
                        isVisible.toggle()
                    }
                }

                Button("Next Change") {
                    withAnimation(.smooth) {
                        sampleIndex = (sampleIndex + 1) % samples.count
                    }
                }
            }
        }
    }

    private struct AnimatedPresenceNumericChangePreview: View {
        @State private var sampleIndex = 0

        private let samples = [
            98,
            104,
            1_248,
            99_300,
            42,
        ]

        var body: some View {
            List {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Numeric content")
                        .lineLimit(1)
                        .font(.headline)

                    AnimatedPresence(
                        value: samples[sampleIndex],
                        animation: .smooth,
                        contentTransition: .numericText()
                    ) { value in
                        Text(value, format: .number)
                            .font(.title2.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Button("Next number") {
                    sampleIndex = (sampleIndex + 1) % samples.count
                }
            }
        }
    }

    // Stack 场景：detail 为 nil 时不应产生残留 spacing。
    private struct AnimatedPresenceStackPreview: View {
        @State private var isVisible = false

        var body: some View {
            CollapsibleSpacingVStack(alignment: .leading) {
                Text("Header")
                    .font(.headline)

                AnimatedPresencePreviewRow(
                    title: "Inline in VStack",
                    detail: isVisible
                        ? "Should collapse to truly zero height when hidden, leaving no residual space between siblings."
                        : nil
                )
                .ignoredWhenCollapsed()

                Text("Footer immediately follows when collapsed.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button(isVisible ? "Hide" : "Show") {
                    isVisible.toggle()
                }
            }
            .padding()
        }
    }

    #Preview("AnimatedPresence - smooth motion") {
        AnimatedPresencePreview()
    }

    #Preview("SwiftUI native height change") {
        SwiftUINativeHeightChangePreview()
    }

    #Preview("AnimatedPresence - numeric") {
        AnimatedPresenceNumericChangePreview()
    }

    #Preview("AnimatedPresence - VStack") {
        AnimatedPresenceStackPreview()
    }

#endif
