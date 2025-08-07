//
//  ExcalidrawCollabContainerView.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 3/13/25.
//

import SwiftUI

extension Notification.Name {
    static let onCreateCollaborationRoom = Notification.Name("OnCreateCollaborationRoom")
    static let onJoinCollaborationRoom = Notification.Name("OnJoinCollaborationRoom")
}

struct ExcalidrawCollabContainerView: View {
    @Environment(\.managedObjectContext) var viewContext
    @Environment(\.alertToast) var alertToast
    @Environment(\.containerHorizontalSizeClass) var containerHorizontalSizeClass
    @EnvironmentObject var appPreference: AppPreference
    @EnvironmentObject var layoutState: LayoutState
    @EnvironmentObject var fileState: FileState

//    var fileBinding: Binding<ExcalidrawFile?> {
//        Binding {
//            do {
//                guard let collabFile = fileState.currentCollaborationFile else {
//                    return nil
//                }
//                return try ExcalidrawFile(
//                    from: collabFile.objectID,
//                    context: viewContext
//                )
//            } catch {
//                alertToast(error)
//            }
//            return nil
//        } set: { val in
//            guard let val else { return }
//            fileState.updateCurrentCollaborationFile(with: val)
//        }
//    }

    @State private var isLoading = false
    @State private var isProgressViewPresented = true
    
    @State private var isCollaborationWebViewOpened = false

    var body: some View {
        ZStack {
            ZStack {
                ForEach(fileState.collaboratingFiles, id: \.self) { file in
                    ExcalidrawCollaborationView(file: file)
                        .zIndex(
                            {
                                if case .collaborationFile(let room) = fileState.currentActiveFile {
                                    return file == room ? 1 : 0
                                } else {
                                    return 0
                                }
                            }()
                        )
                }
            }
            
            if fileState.currentActiveGroup == .collaboration && fileState.currentActiveFile == nil {
                CollaborationHome()
            }
        }
    }
}



#Preview {
    ExcalidrawCollabContainerView()
        .environmentObject(AppPreference())
        .environmentObject(LayoutState())
        .environmentObject(FileState())
        .frame(width: 500)
}

