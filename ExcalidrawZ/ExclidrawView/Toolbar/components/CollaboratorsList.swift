//
//  CollaboratorsList.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 3/17/25.
//

import SwiftUI

import ChocofordUI

struct CollaboratorsList: View {
    
    @Environment(\.dismiss) private var dismiss
    @Environment(\.alertToast) private var alertToast
    @EnvironmentObject private var fileState: FileState
    
    var body: some View {
        ScrollView {
            LazyVStack {
                ForEach(fileState.currentCollaborators, id: \.self) { collaborator in
                    Button {
                        Task {
                            do {
                                try await fileState.excalidrawCollaborationWebCoordinator?.followCollborator(collaborator)
                                dismiss()
                            } catch {
                                alertToast(error)
                            }
                        }
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemSymbol: .personCircle)
                                .font(.title)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(collaborator.username)
                                    .font(.headline)
                                
                                Text(collaborator.userState.rawValue)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .buttonStyle(.listCell)
                }
            }
            .padding()
        }
        .frame(width: 200, height: 240)
    }
}


#if DEBUG
struct CollaboratorsListPreview: View {
    @StateObject private var fileState = FileState()
    
    var body: some View {
        CollaboratorsList()
            .environmentObject(fileState)
//            .onAppear {
//                fileState.collaborators = [
//                    .init(
//                        isCurrentUser: false,
//                        socketID: "",
//                        userState: .active,
//                        username: "123"
//                    )
//                ]
//            }
    }
}

#Preview {
    CollaboratorsListPreview()
}
#endif
