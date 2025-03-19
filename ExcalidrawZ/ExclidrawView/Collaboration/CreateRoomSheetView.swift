//
//  CreateRoomSheetView.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 3/19/25.
//

import SwiftUI

struct CreateRoomSheetView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var collaborationState: CollaborationState
    
    var onCreate: (_ name: String, _ isBlank: Bool) -> Void
    
    init(onCreate: @escaping (_ name: String, _ isBlank: Bool) -> Void) {
        self.onCreate = onCreate
    }
    
    @State private var name: String = "My Room"
    
    var body: some View {
        VStack {
            HStack {
                Text("Create a room")
                Spacer()
            }
            .font(.title)
            
            TextField("Room name", text: $name)
            
            Divider()
            
            HStack {
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Text("Cancel")
                        .frame(width: 60)
                }
                
//                if #available(macOS 13.0, *) {
//                    menuButton()
//                        .menuStyle(.button)
//                } else {
//                    menuButton()
//                        .menuStyle(.borderedButton)
//                }
                Button {
                    dismiss()
                    onCreate(name, true)
                } label: {
                    Text("Create")
                        .frame(width: 60)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .onAppear {
            if !collaborationState.userCollaborationInfo.username.isEmpty {
                name = "\(collaborationState.userCollaborationInfo.username)'s room"
            }
        }
    }
    
    @MainActor @ViewBuilder
    private func menuButton() -> some View {
        Menu {
            Button {
                dismiss()
                onCreate(name, false)
            } label: {
                Text("Create from a file")
            }
            Button {
                dismiss()
                onCreate(name, true)
            } label: {
                Text("Create a blank room")
            }
        } label: {
            Text("Create")
                .frame(width: 60)
        } primaryAction: {
            dismiss()
            onCreate(name, true)
        }
        .buttonStyle(.borderedProminent)
        .fixedSize()
        .disabled(name.isEmpty)
        .tint(.accent)
    }
}
