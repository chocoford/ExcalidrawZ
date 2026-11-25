import SwiftUI
import UniformTypeIdentifiers

struct LinkedStorageRootOrder {
    private(set) var ids: [String]

    init(savedOrder: String, defaultIDs: [String]) {
        var remaining = Set(defaultIDs)
        ids = savedOrder.split(separator: "\n").map(String.init).filter {
            remaining.remove($0) != nil
        }
        ids.append(contentsOf: defaultIDs.filter { remaining.remove($0) != nil })
    }

    var savedOrder: String { ids.joined(separator: "\n") }

    mutating func move(_ sourceID: String, relativeTo destinationID: String, edge: VerticalEdge) -> Bool {
        guard sourceID != destinationID,
              let source = ids.firstIndex(of: sourceID),
              let destination = ids.firstIndex(of: destinationID) else { return false }
        let insertion = destination + (edge == .bottom ? 1 : 0)
        let index = source < insertion ? insertion - 1 : insertion
        guard index != source else { return false }
        ids.remove(at: source)
        ids.insert(sourceID, at: index)
        return true
    }
}

struct SidebarRowReorderAction {
    let item: ItemDragState.DragItem
    let contains: (ItemDragState.DragItem) -> Bool
    let dropTypes: [UTType]
    let move: @MainActor (_ source: ItemDragState.DragItem, _ edge: VerticalEdge) -> Void

    func source(for draggedItem: ItemDragState.DragItem?) -> ItemDragState.DragItem? {
        guard let draggedItem, draggedItem != item, contains(draggedItem) else { return nil }
        return draggedItem
    }
}

struct SidebarRowReorderModifier: ViewModifier {
    @Environment(ItemDragState.self) private var dragState
    let action: SidebarRowReorderAction?

    func body(content: Content) -> some View {
        content.overlay {
            if let action {
                VStack(spacing: 0) {
                    dropZone(edge: .top, action: action)
                    dropZone(edge: .bottom, action: action)
                }
                .allowsHitTesting(action.source(for: dragState.currentDragItem) != nil)
            }
        }
    }

    private func dropZone(
        edge: VerticalEdge,
        action: SidebarRowReorderAction
    ) -> some View {
        let target = ItemDragState.RowReorderTarget(item: action.item, edge: edge)
        return Color.clear
            .contentShape(Rectangle())
            .onDrop(
                of: action.dropTypes,
                delegate: SidebarRowDropDelegate(
                    onTargeted: { isTargeted in
                        if isTargeted {
                            dragState.currentRowReorderTarget = target
                        } else if dragState.currentRowReorderTarget == target {
                            dragState.currentRowReorderTarget = nil
                        }
                    },
                    onDrop: { source, _ in
                        dragState.reset()
                        // Apply the new order after SwiftUI has finished the drop callback.
                        DispatchQueue.main.async {
                            action.move(source, edge)
                        }
                    },
                    resolveLocalDrag: { action.source(for: dragState.currentDragItem) }
                )
            )
            .overlay(alignment: edge == .top ? .top : .bottom) {
                if dragState.currentRowReorderTarget == target {
                    DropTargetPlaceholder()
                        .allowsHitTesting(false)
                }
            }
            .simultaneousGesture(TapGesture().onEnded { dragState.reset() })
    }
}

struct CloudStorageLocationDragModifier: ViewModifier {
    @Environment(ItemDragState.self) private var dragState
    let locationID: UUID

    func body(content: Content) -> some View {
        content
            .opacity(dragState.currentDragItem == .cloudStorageLocation(locationID) ? 0.3 : 1)
            .contentShape(Rectangle())
            .onDrag {
                dragState.currentDragItem = .cloudStorageLocation(locationID)
                return NSItemProvider(
                    item: Data(locationID.uuidString.utf8) as NSData,
                    typeIdentifier: UTType.excalidrawLinkedStorageRoot.identifier
                )
            }
    }
}

extension UTType {
    static let excalidrawLinkedStorageRoot = UTType(exportedAs: "com.chocoford.excalidrawLinkedStorageRoot", conformingTo: .data)
}
