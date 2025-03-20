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
                        Text(.localizable(.collaborationHomeTitle))
                            .font(.largeTitle)
                        
                        Text(.localizable(.collaborationHomeSubtitle))
                        
                        Text(.localizable(.collaborationHomeDescription))
                            .fixedSize(horizontal: false, vertical: true)
                            .multilineTextAlignment(.center)
                    }

                    VStack(spacing: 10) {
                        TextField(
                            .localizable(.collaborationHomeNameFieldLabel),
                            text: $collaborationState.userCollaborationInfo.username,
                            prompt: Text(.localizable(.collaborationHomeNameFieldPlaceholder))
                        )
                        .textFieldStyle(.outlined)
                        .focused($focusFied, equals: FocusField.username)
                        .popover(
                            isPresented: .constant(collaborationState.userCollaborationInfo.username.isEmpty),
                            arrowEdge: .top
                        ) {
                            Text(.localizable(.collaborationHomeNameFieldRequiredPopover))
                                .padding(10)
                        }
                        
                        Divider()
                        
                        SwiftUI.Group {
                            Button {
                                collaborationState.isCreateRoomConfirmationDialogPresented.toggle()
                            } label: {
                                Text(.localizable(.collaborationButtonCreateNewRoom))
                                    .frame(width: 150)
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)
                            
                            Button {
                                collaborationState.isJoinRoomSheetPresented.toggle()
                            } label: {
                                Text(.localizable(.collaborationButtonJoinRoom))
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
