//
//  CollaborationHome.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 3/18/25.
//

import SwiftUI

import ChocofordUI

struct CollaborationHome: View {
    @Environment(\.alertToast) var alertToast
    
    @EnvironmentObject private var fileState: FileState
    @EnvironmentObject private var collaborationState: CollaborationState

    @State private var userName = ""
    
    enum FocusField: Hashable {
        case username
    }
    
    @FocusState private var focusFied: FocusField?

    var body: some View {
        Color.clear
            .contentShape(Rectangle())
            .onTapGesture {
                focusFied = nil
            }
            .overlay {
                VStack(spacing: 40) {
                    VStack(spacing: 20) {
                        Text("Live Collaboration")
                            .font(.largeTitle)
                        
                        Text("Invite people to collaborate on your drawing.")
                        
                        Text("Don't worry, the session is end-to-end encrypted, and fully private. Not even our server can see what you draw.")
                            .fixedSize(horizontal: false, vertical: true)
                            .multilineTextAlignment(.center)
                    }

                    VStack(spacing: 10) {
                        TextField(
                            "Your name",
                            text: $collaborationState.userCollaborationInfo.username,
                            prompt: Text("Your name")
                        )
                        .textFieldStyle(.outlined)
                        .focused($focusFied, equals: FocusField.username)
                        .popover(
                            isPresented: .constant(collaborationState.userCollaborationInfo.username.isEmpty),
                            arrowEdge: .top
                        ) {
                            Text("Please fill your name")
                                .padding(10)
                        }
                        
                        Divider()
                        
                        SwiftUI.Group {
                            Button {
                                collaborationState.isCreateRoomConfirmationDialogPresented.toggle()
                            } label: {
                                Text("Create a new room")
                                    .frame(width: 150)
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)
                            
                            Button {
                                collaborationState.isJoinRoomSheetPresented.toggle()
                            } label: {
                                Text("Join a room")
                                    .frame(width: 150)
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)
                        }
                        .disabled(collaborationState.userCollaborationInfo.username.isEmpty)
                    }
                }
                .frame(maxWidth: 400)
                .padding(80)
            }
    }
    
}

#Preview {
    CollaborationHome()
}
