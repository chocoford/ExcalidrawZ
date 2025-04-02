//
//  ContentViewDetail.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 4/1/25.
//

import SwiftUI

struct ContentViewDetail: View {
    @EnvironmentObject var fileState: FileState
    
    var body: some View {
        ExcalidrawContainerView()
           .modifier(ExcalidrawContainerToolbarContentModifier())
           .opacity(fileState.isInCollaborationSpace ? 0 : 1)
           .overlay {
               ExcalidrawCollabContainerView()
                   .opacity(fileState.isInCollaborationSpace ? 1 : 0)
                   .allowsHitTesting(fileState.isInCollaborationSpace)
           }
    }
}
