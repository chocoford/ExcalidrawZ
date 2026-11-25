//
//  CreateRoomSheetView.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 3/19/25.
//

import SwiftUI

struct CreateRoomSheetView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(CollaborationState.self) private var collaborationState
    
    var onCreate: (_ name: String, _ isBlank: Bool) -> Void
    
    init(onCreate: @escaping (_ name: String, _ isBlank: Bool) -> Void) {
        self.onCreate = onCreate
    }
    
    @State private var name: String = ""
    
    var body: some View {
        VStack {
            HStack {
                Text(.localizable(.collaborationCreateRoomSheetTitle))
                Spacer()
            }
            .font(.title)
            
            TextField(.localizable(.collaborationCreateRoomSheetNameFieldLabel), text: $name)
            
            Divider()
            
            HStack {
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Text(.localizable(.generalButtonCancel))
                        .frame(width: 60)
                }
                .modernButtonStyle(style: .glass, shape: .modern)

                Button {
                    dismiss()
                    onCreate(name, true)
                } label: {
                    Text(.localizable(.generalButtonCreate))
                        .frame(width: 60)
                }
                .modernButtonStyle(style: .glassProminent, shape: .modern)
            }
        }
        .padding()
        .onAppear {
            if !collaborationState.userCollaborationInfo.username.isEmpty {
                name = String(localizable: .collaborationCreateRoomSheetDefaultRoomName(collaborationState.userCollaborationInfo.username))
            }
        }
    }
}
