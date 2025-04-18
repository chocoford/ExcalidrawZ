//
//  ContentViewDetail.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 4/1/25.
//

import SwiftUI

import ChocofordUI

struct ContentViewDetail: View {
    @EnvironmentObject var fileState: FileState
    
    @StateObject private var toolState = ToolState()

    var body: some View {
        ExcalidrawContainerView()
           .modifier(ExcalidrawContainerToolbarContentModifier())
#if os(iOS)
           .modifier(ApplePencilToolbarModifier())
#endif
           .opacity(fileState.isInCollaborationSpace ? 0 : 1)
           .overlay {
               ExcalidrawCollabContainerView()
                   .opacity(fileState.isInCollaborationSpace ? 1 : 0)
                   .allowsHitTesting(fileState.isInCollaborationSpace)
           }
           .environmentObject(toolState)
    }
    
    private func applyToolStateWebCoordinator() {
        // TODO: Not Good Enough
//        DispatchQueue.main.async {
//            print("=-=-=-=-=-=", fileState.excalidrawWebCoordinator, fileState.excalidrawCollaborationWebCoordinator)
//            if fileState.currentCollaborationFile != nil {
//                toolState.excalidrawWebCoordinator = fileState.excalidrawCollaborationWebCoordinator
//            } else {
//                toolState.excalidrawWebCoordinator = fileState.excalidrawWebCoordinator
//            }
//        }
    }
}
