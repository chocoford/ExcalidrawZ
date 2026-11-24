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

struct LinkedStorageRootReorderAction {
    let item: ItemDragState.DragItem
    let contains: (ItemDragState.DragItem) -> Bool
    let move: @MainActor (_ source: ItemDragState.DragItem, _ edge: VerticalEdge) -> Void

    func source(for draggedItem: ItemDragState.DragItem?) -> ItemDragState.DragItem? {
        guard let draggedItem, draggedItem != item, contains(draggedItem) else { return nil }
        return draggedItem
    }
}

struct LinkedStorageRootReorderModifier: ViewModifier {
    @Environment(ItemDragState.self) private var dragState
    let action: LinkedStorageRootReorderAction?

    func body(content: Content) -> some View {
        content.overlay {
            if let action {
                VStack(spacing: 0) {
                    dropZone(edge: .top, target: .startOfGroup(action.item), action: action)
                    dropZone(edge: .bottom, target: .after(action.item), action: action)
                }
                .allowsHitTesting(action.source(for: dragState.currentDragItem) != nil)
            }
        }
    }

    private func dropZone(
        edge: VerticalEdge,
        target: ItemDragState.FileRowDropTarget,
        action: LinkedStorageRootReorderAction
    ) -> some View {
        Color.clear
            .contentShape(Rectangle())
            .onDrop(
                of: [.excalidrawLocalFolderRow, .excalidrawLinkedStorageRoot],
                delegate: SidebarRowDropDelegate(
                    onTargeted: { isTargeted in
                        if isTargeted {
                            dragState.currentDropFileRowTarget = target
                        } else if dragState.currentDropFileRowTarget == target {
                            dragState.currentDropFileRowTarget = nil
                        }
                    },
                    onDrop: { source in
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
                if dragState.currentDropFileRowTarget == target {
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
