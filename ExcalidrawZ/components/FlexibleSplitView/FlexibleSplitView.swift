//
//  FlexibleSplitView.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 7/30/25.
//

import SwiftUI
import ChocofordUI

protocol FlexibleItem {
    var title: String { get }
}

@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
struct FlexibleSplitView<Item: FlexibleItem, ID: Hashable & Transferable>: View {
    @Binding var items: [Item]
    var itemID: KeyPath<Item, ID>
    var arrangement: Binding<SplitArrangement>?
    var subViewBuilder: (Binding<Item>) -> AnyView
    var closeCallback: (Item) -> Void
    
    init<SubView: View>(
        items: Binding<[Item]>,
        arrangement: Binding<SplitArrangement>? = nil,
        closeCallback: @escaping (Item) -> Void,
        @ViewBuilder subView: @escaping (Binding<Item>) -> SubView
    ) where Item: Identifiable, ID == Item.ID {
        self._items = items
        self.itemID = \Item.id
        self.arrangement = arrangement
        self.closeCallback = closeCallback
        self.subViewBuilder = { AnyView(subView($0)) }
    }
        
    
    init<SubView: View>(
        items: Binding<[Item]>,
        id: KeyPath<Item, ID>,
        arrangement: Binding<SplitArrangement>? = nil,
        closeCallback: @escaping (Item) -> Void,
        @ViewBuilder subView: @escaping (Binding<Item>) -> SubView
    ) where Item: Hashable {
        self._items = items
        self.itemID = id
        self.arrangement = arrangement
        self.closeCallback = closeCallback
        self.subViewBuilder = { AnyView(subView($0)) }
    }

    @State private var ratioA: CGFloat = 0.5
    @State private var ratioB: CGFloat = 0.5
    
    @State private var draggedItemID: ID? = nil
    
    @State private var localArrangement: SplitArrangement = .single

    private var layoutRatios: [CGFloat] {
        switch localArrangement {
            case .horizontal, .vertical: return [ratioA]
            case .oneTopTwoBottom, .twoTopOneBottom,
                    .oneLeftTwoRight, .twoLeftOneRight: return [ratioA, ratioB]
            case .single: fallthrough
            default: return []
        }
    }

    var body: some View {
        FlexibleSplitLayout(arrangement: localArrangement, ratios: layoutRatios, spacing: 4) {
            ForEach($items, id: itemID) { item in
                Hover(animation: .smooth) { isHovered in
                    subViewBuilder(item)
                        .modifier(SubViewToolbarModifier {
                            HStack(spacing: 8) {
                                Button {
                                    closeCallback(item.wrappedValue)
                                } label: {
                                    Image(systemSymbol: .xmarkCircle)
                                }
                                
                                Text(item.wrappedValue.title)
                                
                                Menu {
                                    ForEach(SplitArrangement.cases(splitCount: items.count), id: \.self) { arrangement in
                                        Button {
                                            withAnimation {
                                                self.localArrangement = arrangement
                                            }
                                        } label: {
                                            arrangement.iconView()
                                        }
                                    }
                                } label: {
                                    Image(systemSymbol: .rectangle3Group)
                                }
                                
                                dragHandle(for: item.wrappedValue)
                            }
                            .font(.headline)
                            .buttonStyle(.borderless)
                            .padding(6)
                            .background {
                                Rectangle()
                                    .fill(.regularMaterial)
                            }
                        })
                        .dropDestination(for: ID.self) { items, _ in
                            self.draggedItemID = nil
                            return false
                        } isTargeted: { isTargeted in
                            let dst = item.wrappedValue[keyPath: itemID]
                            guard isTargeted else { return }
//                            print(draggedItemID, "draggedIndex: \(items.firstIndex(where: {$0[keyPath: itemID] == draggedItemID})), dstIndex: \(items.firstIndex(where: {$0[keyPath: itemID] == dst}))")
                            withAnimation {
                                if let draggedIndex = items.firstIndex(where: {$0[keyPath: itemID] == draggedItemID}),
                                   let dstIndex = items.firstIndex(where: {$0[keyPath: itemID] == dst}) {
                                    if draggedIndex < dstIndex {
                                        let dragged = items.remove(at: draggedIndex)
                                        items.insert(dragged, at: dstIndex-1)
                                        
                                        let swappedItem = items.remove(at: dstIndex)
                                        items.insert(swappedItem, at: draggedIndex)
                                    } else if draggedIndex > dstIndex {
                                        let dragged = items.remove(at: draggedIndex)
                                        items.insert(dragged, at: dstIndex)
                                        
                                        let swappedItem = items.remove(at: dstIndex+1)
                                        items.insert(swappedItem, at: draggedIndex)
                                    }
                                }
                            }
                        }
                }
            }
        }
        .modifier(
            DividerOverlayModifier(
                arrangement: localArrangement,
                ratioA: $ratioA,
                ratioB: $ratioB
            )
        )
        .onChange(of: arrangement?.wrappedValue) { newValue in
            guard let newValue else { return }
            self.localArrangement = newValue
        }
        .onChange(of: localArrangement) { newValue in
            self.arrangement?.wrappedValue = newValue
        }
        .watchImmediately(of: items.count) { newValue in
            self.localArrangement = SplitArrangement.cases(splitCount: newValue).first ?? .single
        }
    }

    @ViewBuilder
    private func dragHandle(for item: Item) -> some View {
        Color.clear
            .frame(width: 24, height: 24)
            .overlay {
                Image("circle.grid.2x3.fill")
                    .foregroundStyle(.primary)
            }
            .contentShape(Rectangle())
            .draggable(item[keyPath: itemID]) {
                Text(item.title)
                    .fixedSize()
                    .font(.largeTitle)
                    .padding(40)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
//                    .onAppear {
//                        print("Dragging item: \(item.title), ID: \(item[keyPath: itemID])")
//                        self.draggedItemID = item[keyPath: itemID]
//                    }
            }
            .simultaneousGesture(DragGesture(minimumDistance: 0).onChanged { _ in
                print("Dragging item: \(item.title), ID: \(item[keyPath: itemID])")
                if self.draggedItemID != item[keyPath: itemID] {
                    self.draggedItemID = item[keyPath: itemID]
                }
            })
    }
}

@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
fileprivate struct DividerOverlayModifier: ViewModifier {
    let arrangement: SplitArrangement
    @Binding var ratioA: CGFloat
    @Binding var ratioB: CGFloat
    @State private var activeDivider: DividerType? = nil
    
    enum DividerType { case primary, secondary }
    
    @State private var size: CGSize = .zero
    
    @State private var mouseMovedMonitor: Any? = nil
    
    var resizeCursor: NSCursor {
        // 根据当前激活的分割线类型切换对应光标
        switch (arrangement, activeDivider) {
                // 垂直分割线 → 左右拖动
            case (.horizontal, .primary),
                (.oneLeftTwoRight, .primary),
                (.twoLeftOneRight, .primary):
                return NSCursor.resizeLeftRight
                
                // 水平分割线 → 上下拖动
            case (.vertical, .primary),
                (.oneTopTwoBottom, .primary),
                (.twoTopOneBottom, .primary):
                return NSCursor.resizeUpDown
                
                // 二级分割线：上下次分割线属于左右拖动
            case (.oneTopTwoBottom, .secondary),
                (.twoTopOneBottom, .secondary):
                return NSCursor.resizeLeftRight
                
                // 二级分割线：左右次分割线属于上下拖动
            case (.oneLeftTwoRight, .secondary),
                (.twoLeftOneRight, .secondary):
                return NSCursor.resizeUpDown
                
            default:
                return NSCursor.arrow
        }
    }
    
    func body(content: Content) -> some View {
        content
            .readSize($size)
            .overlay {
                MouseMoveTrackingView { localPt in
                    // localPt 是视图左下原点的坐标，和 size 对齐
                    print("Mouse moved at: \(localPt), size: \(size)")
                    activeDivider = detectDivider(at: NSPoint(x: localPt.x, y: size.height - localPt.y), in: size)
                    resizeCursor.set()
                }
            }
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let loc = value.location
                        // 首次确定操作哪条分割线
                        guard activeDivider != nil else { return }
                        // 根据激活的分割线更新 ratio
                        switch activeDivider {
                            case .primary:   updatePrimary(with: loc, in: size)
                            case .secondary: updateSecondary(with: loc, in: size)
                            case .none:      break
                        }
                    }
                    .onEnded { _ in activeDivider = nil }
            )
    }
    
    private func detectDivider(at loc: CGPoint, in size: CGSize, threshold: CGFloat = 10) -> DividerType? {
        switch arrangement {
            case .horizontal:
                let x = size.width * ratioA
                return abs(loc.x - x) < threshold ? .primary : nil
                
            case .vertical:
                let y = size.height * ratioA
                return abs(loc.y - y) < threshold ? .primary : nil
                
            case .oneTopTwoBottom:
                let y = size.height * ratioA
                if abs(loc.y - y) < threshold { return .primary }
                let bottomY = y, x = size.width * ratioB
                if loc.y >= bottomY && abs(loc.x - x) < threshold { return .secondary }
                return nil
                
            case .twoTopOneBottom:
                let y = size.height * ratioA
                if abs(loc.y - y) < threshold { return .primary }
                let x = size.width * ratioB
                if loc.y <= y && abs(loc.x - x) < threshold { return .secondary }
                return nil
                
            case .oneLeftTwoRight:
                let x = size.width * ratioA
                if abs(loc.x - x) < threshold { return .primary }
                let y = size.height * ratioB
                if loc.x >= x && abs(loc.y - y) < threshold { return .secondary }
                return nil
                
            case .twoLeftOneRight:
                let x = size.width * ratioA
                if abs(loc.x - x) < threshold { return .primary }
                let y = size.height * ratioB
                if loc.x <= x && abs(loc.y - y) < threshold { return .secondary }
                return nil
                
            default:
                return nil
        }
    }
    
    private func updatePrimary(with loc: CGPoint, in size: CGSize) {
        switch arrangement {
            case .horizontal: ratioA = loc.x / size.width
            case .vertical: ratioA = loc.y / size.height
            case .oneTopTwoBottom, .twoTopOneBottom:
                ratioA = loc.y / size.height
            case .oneLeftTwoRight, .twoLeftOneRight:
                ratioA = loc.x / size.width
            default: break
        }
        ratioA = min(max(ratioA, 0.1), 0.9)
    }
    
    private func updateSecondary(with loc: CGPoint, in size: CGSize) {
        switch arrangement {
            case .oneTopTwoBottom,
                    .twoTopOneBottom:    ratioB = loc.x / size.width
            case .oneLeftTwoRight,
                    .twoLeftOneRight:    ratioB = loc.y / size.height
            default: break
        }
        ratioB = min(max(ratioB, 0.1), 0.9)
    }
}

fileprivate struct SubViewToolbarModifier: ViewModifier {
    
    var content: AnyView
    
    init<Content: View>(content: () -> Content) {
        self.content = AnyView(content())
    }
     
    @State private var isHovered = false
    @State private var isTopAreaHovered = false
    
    @State private var height: CGFloat = .zero
    
    func body(content: Content) -> some View {
        content
            .readHeight($height)
            .overlay {
                EdgeHoverView(edge: .top, percentage: 0.2) { isHovered in
                    withAnimation {
                        self.isHovered = isHovered
                    }
                }
            }
            .overlay(alignment: .top) {
                if isHovered {
                    self.content
                        .transition(.move(edge: .top))
                }
            }
            .clipShape(Rectangle())
    }
    
    
//    @MainActor @ViewBuilder
//    private func toolbarContent() -> some View {
//        content
//            .padding(6)
//            .background {
//                Rectangle()
//                    .fill(.regularMaterial)
//            }
//    }
}


/// 一个只监听 mouseMoved，不拦截任何点击/拖拽事件的透明 NSView
struct MouseMoveTrackingView: NSViewRepresentable {
    /// 每次 mouseMoved 都给你一个本地坐标 (左下原点)
    var onMouseMoved: (CGPoint) -> Void

    func makeNSView(context: Context) -> TrackingNSView {
        let v = TrackingNSView()
        v.onMouseMoved = onMouseMoved
        return v
    }

    func updateNSView(_ nsView: TrackingNSView, context: Context) {
        nsView.onMouseMoved = onMouseMoved
        nsView.needsLayout = true
    }

    class TrackingNSView: NSView {
        var onMouseMoved: ((CGPoint)->Void)?
        private var trackingArea: NSTrackingArea?

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            if let old = trackingArea {
                removeTrackingArea(old)
            }
            let opts: NSTrackingArea.Options = [
                .mouseMoved, .activeAlways, .inVisibleRect
            ]
            trackingArea = NSTrackingArea(rect: bounds,
                                          options: opts,
                                          owner: self,
                                          userInfo: nil)
            addTrackingArea(trackingArea!)
        }

        override func mouseMoved(with event: NSEvent) {
            // 这里直接转到本地坐标（左下原点）
            let localPt = convert(event.locationInWindow, from: nil)
            onMouseMoved?(localPt)
        }

        // 透传所有点击/拖拽
        override func hitTest(_ point: NSPoint) -> NSView? {
            nil
        }
    }
}
