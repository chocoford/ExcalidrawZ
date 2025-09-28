//
//  LocalFileRow+DragMove.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 8/18/25.
//

import SwiftUI
import UniformTypeIdentifiers

struct LocalFileDragModifier: ViewModifier {
    @EnvironmentObject private var sidebarDragState: ItemDragState

    var file: URL

    init(file: URL) { self.file = file }

    @State private var isDragging = false

    func body(content: Content) -> some View {
        content
            .opacity(sidebarDragState.currentDragItem == .localFile(file) ? 0.3 : 1)
            .onDrag {
                let url = file
                withAnimation { isDragging = true }
                sidebarDragState.currentDragItem = .localFile(url)
                return NSItemProvider(
                    item: url.dataRepresentation as NSData,
                    typeIdentifier: UTType.fileURL.identifier
                )
            }
    }
}
