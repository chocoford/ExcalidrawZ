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
           .opacity(fileState.isInCollaborationSpace ? 0 : 1)
           .overlay {
               ExcalidrawCollabContainerView()
                   .opacity(fileState.isInCollaborationSpace ? 1 : 0)
                   .allowsHitTesting(fileState.isInCollaborationSpace)
           }
           .environmentObject(toolState)
//           .onChange(of: fileState.currentCollaborationFile) { newValue in
//               applyToolStateWebCoordinator()
//           }
//           .onChange(of: fileState.isInCollaborationSpace) { newValue in
//               applyToolStateWebCoordinator()
//           }
//           .onAppear {
//               applyToolStateWebCoordinator()
//           }
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
