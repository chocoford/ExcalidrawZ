//
//  CreateGroupSheetView.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 3/3/25.
//

import SwiftUI

struct CreateGroupSheetView: View {
    @Environment(\.dismiss) var dismiss
    
    init(
        name: Binding<String>,
        createType: CreateGroupType?,
        onCreate: @escaping (_ name: String) -> Void
    ) {
        self._name = name
        if let createType {
            self._createType = State(initialValue: createType)
            canSelectCreateType = true
        } else {
            canSelectCreateType = false
        }
        self.onCreate = onCreate
    }
    
    var onCreate: (_ name: String) -> Void
    
    
    @Binding private var name: String
    
    enum CreateGroupType: Hashable {
        case group
        case localFolder
    }
    
    @State private var createType: CreateGroupType = .group
    var canSelectCreateType: Bool
    
    var body: some View {
        Form {
            Section {
//                HStack {
//                    Text("type:").frame(width: 40, alignment: .trailing)
//                    
//                    Picker(selection: $createType) {
//                        Text("Group").tag(CreateGroupType.group)
//                        Text("Folder").tag(CreateGroupType.localFolder)
//                    } label: {
//                        Text("type:")
//                    }
//                    .pickerStyle(.segmented)
//                    .fixedSize()
//                    .disabled(!canSelectCreateType)
//                }
                
                HStack {
#if os(macOS)
                    Text(.localizable(.sidebarGroupListCreateGroupName))
                        .frame(width: 40, alignment: .trailing)
#endif
                    TextField(.localizable(.sidebarGroupListCreateGroupName), text: $name)
                        .submitLabel(.done)
#if os(macOS)
                        .textFieldStyle(.roundedBorder)
#endif
                        .onSubmit {
                            if !name.isEmpty {
                                onCreate(name)
                                dismiss()
                            }
                        }
                }
            } header: {
                Text(createType == .group ? .localizable(.sidebarGroupListCreateTitle) : .localizable(.sidebarGroupListCreateFolderTitle))
                    .fontWeight(.bold)
            } footer: {
                HStack {
                    Spacer()
                    Button(.localizable(.sidebarGroupListCreateButtonCancel)) { dismiss() }
                    Button(.localizable(.sidebarGroupListCreateButtonCreate)) {
                        onCreate(name)
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(name.isEmpty)
                }
            }
//#if os(macOS)
//            Divider()
//#endif
            
        }
        .labelsHidden()
#if os(macOS)
        .padding()
#endif
    }
    

}

#Preview {
    CreateGroupSheetView(name: .constant(""), createType: .group) { newName in
        
    }
}
