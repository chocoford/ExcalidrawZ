//
//  ItemDragState.swift
//  ExcalidrawZ
//
//  Created by Chocoford on 8/22/25.
//

import SwiftUI

class ItemDragState: ObservableObject {
    enum DragItem: Hashable {
        case group(NSManagedObjectID)
        case file(NSManagedObjectID)
        case localFolder(NSManagedObjectID)
        case localFile(URL)
    }
    
    @Published var currentDragItem: DragItem?
    
    enum FileRowDropTarget: Equatable {
        case after(DragItem)
        case startOfGroup(DragItem)
    }
    @Published var currentDropFileRowTarget: FileRowDropTarget?
    
    enum GroupDropTarget: Equatable {
        case exact(DragItem)
        case below(DragItem)
    }
    
    @Published var currentDropGroupTarget: GroupDropTarget?
    
    var hasAnyDragState: Bool {
        currentDragItem != nil ||
        currentDropFileRowTarget != nil ||
        currentDropGroupTarget != nil
    }
    
    func reset() {
        self.currentDragItem = nil
        self.currentDropGroupTarget = nil
        self.currentDropFileRowTarget = nil
    }
}

struct DragStateModifier: ViewModifier {
    
    @StateObject private var dragState = ItemDragState()

    func body(content: Content) -> some View {
        content
            .modifier(ItemDropFallbackModifier())
            .modifier(ItemDropGlobalFallbackModifier())
            .environmentObject(dragState)
    }
}

struct ItemDropFallbackModifier: ViewModifier {
    @EnvironmentObject private var dragState: ItemDragState
    
    func body(content: Content) -> some View {
        content
//            .simultaneousGesture(
//                TapGesture().onEnded {
//                    dragState.reset()
//                    print("ItemDropFallbackModifier: TapGesture 222")
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
//                        print("ItemDropFallbackModifier: \(isTargeted)")
//                    },
//                    onDrop: { item in
//                        print("ItemDropFallbackModifier: onDrop \(item)")
//                    }
//                )
//            )
//            .background {
//                Color.red.opacity(0.2)
//            }
    }
}


struct ItemDropGlobalFallbackModifier: ViewModifier {
    @EnvironmentObject private var dragState: ItemDragState
    
    func body(content: Content) -> some View {
        content
#if os(macOS)
            .onAppear {
                NSEvent.addLocalMonitorForEvents(matching: .mouseMoved) { event in
                    if dragState.hasAnyDragState {
                        dragState.reset()
                    }
                    return event
                }
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
