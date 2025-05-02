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
    
    @Binding var isSettingsPresented: Bool
    
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
#if os(iOS)
           .modifier(ApplePencilToolbarModifier())
           .sheet(isPresented: $isSettingsPresented) {
               if #available(macOS 13.0, iOS 16.4, *) {
                   SettingsView()
                       .presentationContentInteraction(.scrolls)
               } else {
                   SettingsView()
               }
           }
#endif
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
