//
//  ApplePencilToolbar.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 2/6/25.
//

import SwiftUI

extension Notification.Name {
    static let didPencilConnected = Notification.Name("didPencilConnected")
}

#if os(iOS)
struct ApplePencilToolbarModifier: ViewModifier {
    @AppStorage("isFirstOpenPencilMode") private var isFirstOpenPencilMode = true

    @Environment(\.alertToast) var alertToast
    @EnvironmentObject private var toolState: ToolState

    @State private var toolbarOffset: CGSize = .zero
    @State private var prevToolbarOffset: CGSize = .zero
    
    @State private var viewSize: CGSize = .zero
    @State private var toolbarSize: CGSize = .zero
    
    @State private var isDragging: Bool = false
    @State private var isExpanded: Bool = false
    
    @State private var expansionDirection: Axis = .horizontal
    @State private var expansionHandlerOffset: CGSize = .zero

    @State private var toolbarAlignment: Alignment = .bottomTrailing
    
    @State private var isPencilModeTipsPresented = false
    

    
    /// 工具栏与屏幕边缘的最小间距
    private let margin: CGFloat = 16
    
    private var handlerAligment: Alignment {
        switch expansionDirection {
            case .horizontal:
                switch toolbarAlignment {
                    case .topLeading, .topTrailing:
                        return .bottom
                    case .bottomLeading, .bottomTrailing:
                        return .top
                    default:
                        return .center
                }
            case .vertical:
                switch toolbarAlignment {
                    case .topLeading, .bottomLeading:
                        return .trailing
                    case .topTrailing, .bottomTrailing:
                        return .leading
                    default:
                        return .center
                }
        }
    }
    private var settingToggleOffset: CGSize {
        let x = 40
        let y = 40
        switch toolbarAlignment {
            case .topLeading:
                return CGSize(width: x, height: y)
            case .topTrailing:
                return CGSize(width: -x, height: y)
            case .bottomLeading:
                return CGSize(width: x, height: -y)
            case .bottomTrailing:
                return CGSize(width: -x, height: -y)
            default:
                return .zero
        }
    }
    
    func body(content: Content) -> some View {
        content
            .overlay {
                if toolState.inPenMode {
                    ZStack(alignment: toolbarAlignment) {
                        Color.clear
                            .contentShape(Rectangle())
                            .onTapGesture {
                                if isExpanded {
                                    isExpanded = false
                                }
                            }
                            .allowsHitTesting(isExpanded)
                        
                        // Actions Menu Button
                        ZStack {
                            if !isDragging && !isExpanded {
                                Button {
                                    toolState.toggleActionsMenu()
                                } label: {
                                    Color.clear
                                        .frame(width: 20, height: 20)
                                        .overlay {
                                            ZStack {
                                                if toolState.isActionsMenuPresneted {
                                                    Image(systemSymbol: .menucard)
                                                        .resizable()
                                                        .scaledToFit()
                                                } else {
                                                    Image("menucard.slash")
                                                        .resizable()
                                                        .scaledToFit()
                                                }
                                            }
                                            .foregroundStyle(toolState.isActionsMenuPresneted ? .primary : .secondary)
                                        }
                                        .padding(10)
                                        .background {
                                            Circle()
                                                .fill(.background)
                                                .shadow(radius: 8)
                                        }
                                }
                                .hoverEffect(.lift)
                                .padding(.horizontal, 90)
                                .padding(.vertical, 60)
                                .transition(.asymmetric(insertion: .opacity.animation(.default.delay(0.5)), removal: .opacity))
                            }
                        }
                        .animation(.default, value: isDragging)
                        .animation(.default, value: isExpanded)
                        .animation(nil, value: toolbarAlignment)
                        
                        // Delete Button
                        ZStack {
                            if !isDragging && !isExpanded {
                                ZStack {
                                    if !toolState.isBottomBarPresented {
                                        Button(role: .destructive) {
                                            Task {
                                                do {
                                                    try await toolState.toggleDelegeAction()
                                                } catch {
                                                    alertToast(error)
                                                }
                                            }
                                        } label: {
                                            Color.clear
                                                .frame(width: 20, height: 20)
                                                .overlay {
                                                    Image(systemSymbol: .trash)
                                                        .resizable()
                                                        .scaledToFit()
                                                        .foregroundStyle(.red)
                                                }
                                                .padding(10)
                                                .background {
                                                    Circle()
                                                        .fill(.background)
                                                        .shadow(radius: 8)
                                                }
                                        }
                                        .hoverEffect(.lift)
                                        .padding(.horizontal, 90)
                                        .padding(.vertical, 10)
                                    }
                                }
                                .transition(.asymmetric(insertion: .opacity.animation(.default.delay(0.5)), removal: .opacity))
                            }
                        }
                        .animation(.default, value: isDragging)
                        .animation(.default, value: isExpanded)
                        .animation(nil, value: toolbarAlignment)
                        
                        ApplePencilToolbar(isExpanded: $isExpanded, expansionDirection: expansionDirection)
                            .readSize($toolbarSize)
                            .scaleEffect(isDragging || isExpanded ? 1 : 0.8)
                            .animation(.smooth, value: isDragging || isExpanded)
                            .overlay(alignment: handlerAligment) {
                                Capsule()
                                    .fill(.quaternary)
                                    .hoverEffect(expansionDirection == .horizontal ? .lift : .highlight)
                                    .frame(width: expansionDirection == .horizontal ? 50 : 6, height: expansionDirection == .horizontal ? 6 : 50)
                                    .gesture(
                                        DragGesture(minimumDistance: 0, coordinateSpace: .global)
                                            .onChanged { onDragging($0) }
                                            .onEnded { onDragEnd($0) }
                                    )
                                    .padding(10)
                                    .opacity(isExpanded ? 1 : 0.001)
                                    .offset(expansionHandlerOffset)
                            }
                            .offset(toolbarOffset)
//                            .alignmentGuide(.trailing) { d in
//                                (
//                                    d[.trailing] + margin - toolbarOffset.width
//                                )
//                                .clamped(to: (d[.trailing] + margin)...(d[.trailing] + viewSize.width - 2*margin - toolbarSize.width))
//                            }
//                            .alignmentGuide(.bottom) { d in
//                                (
//                                    d[.bottom] + margin - toolbarOffset.height
//                                )
//                                .clamped(to: (d[.bottom] + margin)...(d[.bottom] + viewSize.height - 2*margin - toolbarSize.height))
//                            }
                            .gesture(
                                DragGesture(minimumDistance: 0, coordinateSpace: .global)
                                    .onChanged { onDragging($0) }
                                    .onEnded { onDragEnd($0) },
                                isEnabled: !isExpanded || isDragging
                            )
                            .animation(.smooth, value: isExpanded)
                            .animation(.smooth, value: handlerAligment)
                            .onAppear {
                                toolbarOffset = CGSize(width: -margin, height: -margin)
                            }
                    }
                    .ignoresSafeArea()
                }
            }
            .readSize($viewSize)
            .watch(value: toolState.pencilInteractionMode) { mode in
                guard toolState.inPenMode else { return }
                Task {
                    do {
                        switch mode {
                            case .fingerSelect:
                                try await toolState.togglePencilInterationMode(.fingerSelect)
                            case .fingerMove:
                                try await toolState.togglePencilInterationMode(.fingerMove)
                        }
                    } catch {
                        alertToast(error)
                    }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .didPencilConnected)) { _ in
                if isFirstOpenPencilMode {
                    isPencilModeTipsPresented = true
                    isFirstOpenPencilMode = false
                }
            }
            .sheet(isPresented: $isPencilModeTipsPresented) {
                PencilTipsSheetView()
            }
    }
    
    private func onDragging(_ value: DragGesture.Value) {
        if !isDragging {
            isDragging = true
            switch toolbarAlignment {
                case .topLeading:
                    toolbarOffset = CGSize(
                        width: margin + toolbarSize.width / 2 - viewSize.width / 2,
                        height: margin + toolbarSize.height / 2 - viewSize.height / 2
                    )
                    prevToolbarOffset = toolbarOffset
                case .topTrailing:
                    toolbarOffset = CGSize(
                        width: viewSize.width / 2 - margin - toolbarSize.width / 2,
                        height: margin + toolbarSize.height / 2 - viewSize.height / 2
                    )
                    prevToolbarOffset = toolbarOffset
                case .bottomLeading:
                    toolbarOffset = CGSize(
                        width: margin + toolbarSize.width / 2 - viewSize.width / 2,
                        height: viewSize.height / 2 - margin - toolbarSize.height / 2
                    )
                    prevToolbarOffset = toolbarOffset
                case .bottomTrailing:
                    toolbarOffset = CGSize(
                        width: viewSize.width / 2 - margin - toolbarSize.width / 2,
                        height: viewSize.height / 2 - margin - toolbarSize.height / 2
                    )
                    prevToolbarOffset = toolbarOffset
                default:
                    break
            }
            toolbarAlignment = .center
        }
        withAnimation(.smooth(duration: 0.1)) {
            toolbarOffset = prevToolbarOffset + value.translation
        }

        if viewSize.width > 0, viewSize.height > 0 {
            let containerCenter = CGPoint(x: viewSize.width / 2, y: viewSize.height / 2)
            let currentCenter = containerCenter.applying(.identity.translatedBy(x: toolbarOffset.width, y: toolbarOffset.height))
            
            let regionInset: CGFloat = 80
            let verticalLowerBound = viewSize.height * 0.3
            let verticalUpperBound = viewSize.height * 0.7
            let horizontalLowerBound = viewSize.width * 0.3
            let horizontalUpperBound = viewSize.width * 0.7
            
            var inEdgeRegion = false
            
            // 判断是否在左侧中间区域：x 靠近左边且 y 在中间
            if currentCenter.x <= regionInset &&
                currentCenter.y >= verticalLowerBound &&
                currentCenter.y <= verticalUpperBound {
                inEdgeRegion = true
                expansionDirection = .vertical
                expansionHandlerOffset = CGSize(width: toolbarSize.width / 2 - 10, height: 0)
            }
            // 判断是否在右侧中间区域：x 靠近右边且 y 在中间
            else if currentCenter.x >= (viewSize.width - regionInset) &&
                        currentCenter.y >= verticalLowerBound &&
                        currentCenter.y <= verticalUpperBound {
                inEdgeRegion = true
                expansionDirection = .vertical
                expansionHandlerOffset = CGSize(width: -toolbarSize.width / 2 + 10, height: 0)
            }
            // 判断是否在顶部中间区域：y 靠近上边且 x 在中间
            else if currentCenter.y <= regionInset &&
                        currentCenter.x >= horizontalLowerBound &&
                        currentCenter.x <= horizontalUpperBound {
                inEdgeRegion = true
                expansionDirection = .horizontal
                expansionHandlerOffset = CGSize(width: 0, height: toolbarSize.height / 2 - 10)
            }
            // 判断是否在底部中间区域：y 靠近下边且 x 在中间
            else if currentCenter.y >= (viewSize.height - regionInset) &&
                        currentCenter.x >= horizontalLowerBound &&
                        currentCenter.x <= horizontalUpperBound {
                inEdgeRegion = true
                expansionDirection = .horizontal
                expansionHandlerOffset = CGSize(width: 0, height: -toolbarSize.height / 2 + 10)
            } else {
                expansionHandlerOffset = .zero
            }
            
            // 检测拖拽速度
            // 利用 predictedEndTranslation 与当前 translation 的差值作为速度参考
            let predictedDelta = CGSize(
                width: value.predictedEndTranslation.width - value.translation.width,
                height: value.predictedEndTranslation.height - value.translation.height
            )
            let predictedSpeed = sqrt(predictedDelta.width * predictedDelta.width + predictedDelta.height * predictedDelta.height)
            // 设定速度阈值（单位：pt），低于该阈值认为速度较低
            let speedThreshold: CGFloat = 20
            
            // 如果位置在边缘区域且拖拽速度较低，则触发展开
            if inEdgeRegion, predictedSpeed < speedThreshold {
                if !isExpanded {
                    isExpanded = true
                }
            } else if !inEdgeRegion {
                isExpanded = false
            }
        }
    }
    
    /// Updates the toolbar’s alignment, expansion direction, and offset when a drag gesture ends.
    ///
    /// This function is called at the end of a drag gesture on the Apple Pencil toolbar. It performs the following steps:
    /// 1. **Reset Dragging State:**
    /// It sets the dragging flag to false and resets any expansion handler offset.
    /// 2. **Compute Current Center:**
    /// It calculates the current center of the toolbar by adding the accumulated drag offset to the container’s center.
    /// 3. **Determine Snap Position:**
    /// It defines the ideal center positions for each of the four corners (top-left, top-right, bottom-left, bottom-right) based on the toolbar’s size and a defined margin.
    /// Then, it computes the Euclidean distance from the current center to each of these ideal positions and selects the corner that is closest (the "snapped" position).
    /// 4. **Determine Expansion Direction:**
    /// If the drag translation exceeds a small threshold (to distinguish a tap from a drag), the function compares the horizontal and vertical differences between the current center and the snapped corner’s center.
    /// It sets the expansion direction to horizontal if the horizontal difference is greater than or equal to the vertical difference; otherwise, it sets it to vertical.
    /// If the expansion direction changes, it toggles the expanded state with a slight animation delay.
    /// 5. **Animate Alignment and Reset Offset:**
    /// Finally, it animates the toolbar’s alignment to snap to the chosen corner by updating the toolbarAlignment and resetting the toolbarOffset (and prevToolbarOffset) to a fixed offset determined by the margin.
    /// Additionally, if the overall drag translation is very short (indicating a tap), it toggles the expanded state directly.
    ///
    ///  - Parameter value: The final value of the drag gesture (of type DragGesture.Value), which provides the translation and predicted end translation needed for these calculations.
    private func onDragEnd(_ value: DragGesture.Value) {
        /// Reset Dragging State
        isDragging = false
        expansionHandlerOffset = .zero
        
        
        /// Compute Current Center
        let containerCenter = CGPoint(x: viewSize.width / 2, y: viewSize.height / 2)
        let currentCenter = containerCenter.applying(.identity.translatedBy(x: toolbarOffset.width, y: toolbarOffset.height))
        
        
        /// Determine Snap Position
        let topLeftCenter = CGPoint(
            x: margin + toolbarSize.width / 2,
            y: margin + toolbarSize.height / 2
        )
        let topRightCenter = CGPoint(
            x: viewSize.width - margin - toolbarSize.width / 2,
            y: margin + toolbarSize.height / 2
        )
        let bottomLeftCenter = CGPoint(
            x: margin + toolbarSize.width / 2,
            y: viewSize.height - margin - toolbarSize.height / 2
        )
        let bottomRightCenter = CGPoint(
            x: viewSize.width - margin - toolbarSize.width / 2,
            y: viewSize.height - margin - toolbarSize.height / 2
        )
        
        let distances: [(alignment: Alignment, distance: CGFloat, center: CGPoint)] = [
            (.topLeading, currentCenter.distance(to: topLeftCenter), topLeftCenter),
            (.topTrailing, currentCenter.distance(to: topRightCenter), topRightCenter),
            (.bottomLeading, currentCenter.distance(to: bottomLeftCenter), bottomLeftCenter),
            (.bottomTrailing, currentCenter.distance(to: bottomRightCenter), bottomRightCenter)
        ]
        
        let snapped = distances.min { $0.distance < $1.distance }!
        
        /// Determine Expansion Direction
        let newExpansionDirection: Axis
        if value.translation.distance > 10 {
            let deltaX = abs(currentCenter.x - snapped.center.x)
            let deltaY = abs(currentCenter.y - snapped.center.y)
            if deltaX >= deltaY {
                newExpansionDirection = .horizontal
            } else {
                newExpansionDirection = .vertical
            }
        } else {
            newExpansionDirection = expansionDirection
        }
        if newExpansionDirection != expansionDirection {
            expansionDirection = newExpansionDirection
            withAnimation(.smooth.delay(0.5)) {
                isExpanded.toggle()
            }
        }
        
        /// Animate Alignment and Reset Offset
        withAnimation(.smooth) {
            toolbarAlignment = snapped.alignment
            let offsetXMultiplier: CGFloat = {
                switch snapped.alignment {
                    case .topTrailing, .bottomTrailing:
                        -1
                    default:
                        1
                }
            }()
            let offsetYMultiplier: CGFloat = {
                switch snapped.alignment {
                    case .bottomLeading, .bottomTrailing:
                        -1
                    default:
                        1
                }
            }()
            let newOffset = CGSize(width: offsetXMultiplier * margin, height: offsetYMultiplier * margin)
            toolbarOffset = newOffset
            prevToolbarOffset = newOffset
            
            if value.translation.distance < 10, !isExpanded {
                
                isExpanded.toggle()
            }
        }
    }
    
}

struct ApplePencilToolbar: View {
    @Environment(\.alertToast) private var alertToast
    
    @EnvironmentObject private var toolState: ToolState
    
    @Binding var isExpanded: Bool
    var expansionDirection: Axis
    
    @Namespace var activeToolNamespace
    
    @State private var isMathInputSheetPresented = false

    var body: some View {
        ZStack {
            if isExpanded {
                let layout1 = expansionDirection == .horizontal ? AnyLayout(HStackLayout(spacing: 12)) : AnyLayout(VStackLayout(spacing: 12))
                layout1{
                    let layout2 = expansionDirection == .horizontal ? AnyLayout(HStackLayout(spacing: 6)) : AnyLayout(VStackLayout(spacing: 6))
                    layout2 {
                        ForEach(ExcalidrawTool.allCases, id: \.self) { tool in
                            Button {
                                Task {
                                    do {
                                        try await toolState.toggleTool(tool)
                                        self.isExpanded = false
                                    } catch {
                                        alertToast(error)
                                    }
                                }
                            } label: {
                                Color.clear
                                    .aspectRatio(1, contentMode: .fit)
                                    .overlay {
                                        tool.icon(strokeLineWidth: 2)
                                            .matchedGeometryEffect(
                                                id: tool.rawValue,
                                                in: activeToolNamespace,
                                                properties: .frame,
                                                isSource: true
                                            )
                                            .padding(6)
                                    }
                                    .contentShape(Rectangle())
                                    .hoverEffect()
                            }
                        }
                    }
                    .padding(.vertical, 4)
                    
                    Divider()
                    
                    moreTools()
                    
                    Menu {
                        Button(role: .destructive) {
                            Task {
                                try? await toolState.togglePenMode(enabled: false)
                            }
                        } label: {
                            Label(.localizable(.applePencilButtonDisconnect), systemSymbol: .pencilSlash)
                        }
                        .labelStyle(.titleAndIcon)
                    } label: {
                        Color.clear
                            .aspectRatio(1, contentMode: .fit)
                            .overlay {
                                Label(.localizable(.toolbarMoreTools), systemSymbol: .ellipsis)
                                    .font(.body.bold())
                                    .foregroundStyle(.secondary)
                                    .labelStyle(.iconOnly)
                            }
                            .background {
                                Circle()
                                    .fill(.regularMaterial)
                            }
#if os(iOS)
                            .hoverEffect(.lift)
#endif
                    }
                    .menuIndicator(.hidden)
#if os(iOS)
                    .menuOrder(.fixed)
#endif
                }
            } else if let tool = toolState.activatedTool {
                Color.clear
                    .aspectRatio(1, contentMode: .fit)
                    .overlay {
                        tool.icon(strokeLineWidth: 4)
                            .matchedGeometryEffect(
                                id: tool.rawValue,
                                in: activeToolNamespace,
                                properties: .frame,
                                isSource: false
                            )
                    }
            } else {
                ExcalidrawTool.freedraw.icon()
                    .aspectRatio(1, contentMode: .fit)
                
            }
        }
        .foregroundStyle(.primary)
        .padding(20)
        .clipShape(Capsule())
        .modifier(
            AnimatableContainerSizeModifier(
                targetSize: CGSize(
                    width: expansionDirection == .horizontal ? (isExpanded ? 700 : 80) : 80,
                    height: expansionDirection == .vertical ? (isExpanded ? 700 : 80) : 80
                )
            )
        )
        .background {
            Capsule()
                .fill(.background)
                .shadow(radius: 20)
        }
        .onAppear {
            if toolState.activatedTool == nil {
                Task {
                    try? await toolState.toggleTool(.freedraw)
                }
            }
        }
    }
    
    @MainActor @ViewBuilder
    private func moreTools() -> some View {
        Menu {
            Button {
                Task {
                    try? await toolState.toggleExtraTool(.text2Diagram)
                }
            } label: {
                Text(.localizable(.toolbarText2Diagram))
            }
            Button {
                Task {
                    try? await toolState.toggleExtraTool(.mermaid)
                }
            } label: {
                Text(.localizable(.toolbarMermaid))
            }
            Button {
                isMathInputSheetPresented.toggle()
            } label: {
                Text(.localizable(.toolbarLatexMath))
            }
        } label: {
            Color.clear
                .aspectRatio(1, contentMode: .fit)
                .overlay {
                    if #available(macOS 15.0, iOS 18.0, *) {
                        Label(.localizable(.toolbarMoreTools), systemImage: "xmark.triangle.circle.square")
                    } else {
                        Label(.localizable(.toolbarMoreTools), systemSymbol: .chartXyaxisLine)
                    }
                }
                .font(.body.bold())
                .labelStyle(.iconOnly)
                .foregroundStyle(.secondary)
                .background {
                    Circle().fill(.regularMaterial)
                }
                .hoverEffect(.lift)
        }
        .menuIndicator(.hidden)
#if os(iOS)
        .menuOrder(.fixed)
#endif
        .modifier(MathInputSheetViewModifier(isPresented: $isMathInputSheetPresented))
    }
}

struct AnimatableContainerSizeModifier: Animatable, ViewModifier {
    var targetSize: CGSize
    
    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(targetSize.width, targetSize.height) }
        set { targetSize = CGSize(width: newValue.first, height: newValue.second) }
    }
    
    func body(content: Content) -> some View {
        content
            .frame(width: targetSize.width, height: targetSize.height)
    }
}

struct GeometryGroupModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 17.0, *) {
            content
                .geometryGroup()
        } else {
            content
        }
    }
}


#endif
extension CGSize {
    static func + (_ lhs: CGSize, _ rhs: CGSize) -> CGSize {
        CGSize(width: lhs.width + rhs.width, height: lhs.height + rhs.height)
    }
}

extension Comparable {
    /// 将值限制在指定的闭区间内，如果超出范围则封顶。
    /// - Parameter limits: 闭区间范围
    /// - Returns: 如果值小于下界，则返回下界；如果大于上界，则返回上界；否则返回自身。
    func clamped(to limits: ClosedRange<Self>) -> Self {
        return min(max(self, limits.lowerBound), limits.upperBound)
    }
}

extension CGPoint {
    /// 计算两点之间的欧氏距离
    func distance(to point: CGPoint) -> CGFloat {
        sqrt(pow(self.x - point.x, 2) + pow(self.y - point.y, 2))
    }
}
