//
//  ContentViewDetail.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 4/1/25.
//

import SwiftUI
import CoreData
import SwiftyAlert
#if os(macOS)
import AppKit
#endif

import ChocofordUI
import SplitView

struct ContentViewDetail: View {
    @Environment(\.alertToast) var alertToast

    @EnvironmentObject var fileState: FileState
    
    @Binding var isSettingsPresented: Bool

    var body: some View {
        splitViewsContent()
    }
    
    private func applyToolStateWebCoordinator() {
        // TODO: Not Good Enough
//        DispatchQueue.main.async {
//            if fileState.currentCollaborationFile != nil {
//                toolState.excalidrawWebCoordinator = fileState.excalidrawCollaborationWebCoordinator
//            } else {
//                toolState.excalidrawWebCoordinator = fileState.excalidrawWebCoordinator
//            }
//        }
    }
    
    @ViewBuilder
    private func splitViewsContent() -> some View {
        if #available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *), false {
            ExcalidrawSplitViewsContainer()
        } else if fileState.activeFiles.count > 0 {
            ExcalidrawHomeView(isSettingsPresented: $isSettingsPresented)
                .modifier(FileHomeItemTransitionModifier())
        }
    }
}

extension FileState.ActiveFile: FlexibleItem {
    var title: String {
        name ?? .init(localizable: .generalUntitled)
    }
}

@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
struct ExcalidrawSplitViewsContainer: View {
    @Environment(\.managedObjectContext) var viewContext
    @Environment(\.alertToast) var alertToast

    @EnvironmentObject var fileState: FileState
    
    var body: some View {
//        FlexibleSplitView(items: $fileState.activeFiles) { file in
//            withAnimation {
//                fileState.activeFiles.removeAll(where: {$0?.id == file?.id})
//            }
//        } subView: { activeFile in
//            ExcalidrawEditor(activeFile: activeFile)
//                .modifier(FileHomeItemTransitionModifier())
//        }
    }
}


#Preview {
    if #available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *) {
        
    } else {
        EmptyView()
    }
}
