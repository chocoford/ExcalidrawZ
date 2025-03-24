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
    
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var fileState: FileState
    @EnvironmentObject private var collaborationState: CollaborationState

    @State private var userName = ""
    
    enum FocusField: Hashable {
        case username
    }
    
    @FocusState private var focusFied: FocusField?
    
    @FetchRequest(sortDescriptors: [])
    private var collaborationFiles: FetchedResults<CollaborationFile>
    

    var body: some View {
        Color.clear
            .contentShape(Rectangle())
            .onTapGesture {
                focusFied = nil
            }
            .overlay {
                VStack(spacing: 0) {
                    VStack(spacing: 20) {
                        Text(.localizable(.collaborationHomeTitle))
                            .font(.largeTitle)
                        
                        Text(.localizable(.collaborationHomeSubtitle))
                        
                        Text(.localizable(.collaborationHomeDescription))
                            .fixedSize(horizontal: false, vertical: true)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.horizontal, 80)
                    .padding(.vertical, 60)
                    .background {
                        CollaborationHomeBackground()
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
                                if let limit = store.collaborationRoomLimits, collaborationFiles.count >= limit {
                                    store.togglePaywall(reason: .roomLimit)
                                } else {
                                    collaborationState.isCreateRoomConfirmationDialogPresented.toggle()
                                }
                            } label: {
                                Text(.localizable(.collaborationButtonCreateNewRoom))
                                    .frame(width: 150)
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)
                            
                            Button {
                                if let limit = store.collaborationRoomLimits, collaborationFiles.count >= limit {
                                    store.togglePaywall(reason: .roomLimit)
                                } else {
                                    collaborationState.isJoinRoomSheetPresented.toggle()
                                }
                            } label: {
                                Text(.localizable(.collaborationButtonJoinRoom))
                                    .frame(width: 150)
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)
                        }
                        .disabled(collaborationState.userCollaborationInfo.username.isEmpty)
                    }
                    .padding(.horizontal, 80)
                }
                .frame(maxWidth: 560)
            }
    }
    
}

struct CollaborationHomeBackground: View {
    @State private var isPresented = false
    
    var body: some View {
        ZStack {
            Image("Collaboration/hero-background")
                .resizable()
                .opacity(isPresented ? 0.7 : 0)
                .scaledToFill()
                .scaleEffect(1.2)
            
            Image("Collaboration/collaborator-blue")
                .offset(x: isPresented ? -220 : -800, y: isPresented ? 36 : 400)
            Image("Collaboration/collaborator-green")
                .offset(x: isPresented ? 170 : 1000, y: isPresented ? -70 : -1000)
            Image("Collaboration/collaborator-red")
                .offset(x: isPresented ? -150 : -1000, y: isPresented ? -86 : -1000)
            Image("Collaboration/collaborator-yellow")
                .offset(x: isPresented ? 200 : 1000, y: isPresented ? 90 : 1000)
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                withAnimation(.smooth(duration: 1.2)) {
                    isPresented = true
                }
            }
        }
        .onDisappear {
            isPresented = false
        }
    }
}

#Preview {
    CollaborationHome()
        .environmentObject(Store())
        .environmentObject(FileState())
        .environmentObject(CollaborationState())
}
