//
//  ItemDragState.swift
//  ExcalidrawZ
//
//  Created by Chocoford on 8/22/25.
//

import Observation
import SwiftUI
import CoreData

@Observable
class ItemDragState {
    enum DragItem: Hashable {
        case group(NSManagedObjectID)
        case file(NSManagedObjectID)
        case localFolder(NSManagedObjectID)
        case cloudStorageLocation(UUID)
        case localFile(URL)
        
        case collaborationFile(NSManagedObjectID)
        case temporaryFile(URL)
    }
    
    var currentDragItem: DragItem?
    
    enum FileRowDropTarget: Equatable {
        case after(DragItem)
        case startOfGroup(DragItem)
    }
    var currentDropFileRowTarget: FileRowDropTarget?
    
    enum GroupDropTarget: Equatable {
        case exact(DragItem)
        case below(DragItem)
    }
    
    var currentDropGroupTarget: GroupDropTarget?

    struct RowReorderTarget: Equatable {
        let item: DragItem
        let edge: VerticalEdge
    }
    var currentRowReorderTarget: RowReorderTarget?
    
    var hasAnyDragState: Bool {
        currentDragItem != nil ||
        currentDropFileRowTarget != nil ||
        currentDropGroupTarget != nil ||
        currentRowReorderTarget != nil
    }
    
    func reset() {
        self.currentDragItem = nil
        self.currentDropGroupTarget = nil
        self.currentDropFileRowTarget = nil
        self.currentRowReorderTarget = nil
    }
}

struct DragStateModifier: ViewModifier {
    
    @State private var dragState = ItemDragState()

    func body(content: Content) -> some View {
        content
            .modifier(ItemDropFallbackModifier())
            .modifier(ItemDropGlobalFallbackModifier())
            .modifier(ExcalidrawLibraryDropHandler())
            .environment(dragState)
    }
}

struct ItemDropFallbackModifier: ViewModifier {
    @Environment(ItemDragState.self) private var dragState
    
    func body(content: Content) -> some View {
        content
//            .simultaneousGesture(
//                TapGesture().onEnded {
//                    dragState.reset()
//                }
//            )
//            .modifier(
//                SidebarRowDropModifier(
//                    allow: [
//                        .excalidrawFile,
//                        .excalidrawGroupRow,
//                        .excalidrawLocalFolderRow,
//                        .fileURL
//                    ],
//                    onTargeted: { isTargeted in
//                    },
//                    onDrop: { item in
//                    }
//                )
//            )
//            .background {
//                Color.red.opacity(0.2)
//            }
    }
}


struct ItemDropGlobalFallbackModifier: ViewModifier {
    @Environment(ItemDragState.self) private var dragState
#if os(macOS)
    @State private var mouseMovedMonitor: Any?
#endif
    
    func body(content: Content) -> some View {
        content
#if os(macOS)
            .onAppear {
                guard mouseMovedMonitor == nil else { return }
                mouseMovedMonitor = NSEvent.addLocalMonitorForEvents(matching: .mouseMoved) { event in
                    if dragState.hasAnyDragState {
                        dragState.reset()
                    }
                    return event
                }
            }
            .onDisappear {
                guard let mouseMovedMonitor else { return }
                NSEvent.removeMonitor(mouseMovedMonitor)
                self.mouseMovedMonitor = nil
            }
#endif // os(macOS)
    }
}




extension View {
    func itemDropFallback() -> some View {
        modifier(ItemDropFallbackModifier())
    }
    func itemDropGlobalFallback() -> some View {
        modifier(ItemDropGlobalFallbackModifier())
    }
}
