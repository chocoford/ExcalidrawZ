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

    func body(content: Content) -> some View {
        content
#if os(macOS)
            .opacity(sidebarDragState.currentDragItem == .localFile(file) ? 0.3 : 1)
#endif
            .onDrag {
                let url = file
                sidebarDragState.currentDragItem = .localFile(url)
                return NSItemProvider(
                    item: url.dataRepresentation as NSData,
                    typeIdentifier: UTType.fileURL.identifier
                )
            }
    }
}
