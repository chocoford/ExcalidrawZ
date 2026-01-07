//
//  CreateGroupSheetView.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 3/3/25.
//

import SwiftUI
import CoreData

struct CreateGroupModifier: ViewModifier {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.containerHorizontalSizeClass) private var containerHorizontalSizeClass
    @Environment(\.alertToast) private var alertToast
    @EnvironmentObject var fileState: FileState
    
    @FetchRequest
    var groups: FetchedResults<Group>
    
    @Binding var isPresented: Bool
    var parentGroupID: NSManagedObjectID?
    
    init(isPresented: Binding<Bool>, parentGroupID: NSManagedObjectID?) {
        self._isPresented = isPresented
        self.parentGroupID = parentGroupID
        
        self._groups = FetchRequest(
            sortDescriptors: [
                SortDescriptor(\.createdAt, order: .forward),
            ],
            predicate: parentGroupID != nil
            ? NSPredicate(format: "parent = %@", parentGroupID!)
            : NSPredicate(format: "parent = nil"),
            animation: .smooth
        )
    }
    
    @State private var initialNewGroupName = ""
    
    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $isPresented) {
                if containerHorizontalSizeClass == .compact {
                    createFolderSheetView()
                } else if #available(iOS 18.0, macOS 13.0, *) {
                    createFolderSheetView()
                        .scrollDisabled(true)
#if os(iOS)
                        .frame(width: 400, height: 160)
                        .presentationSizing(.fitted)
#else
                        .frame(width: 400, height: 140)
#endif
                } else {
                    createFolderSheetView()
                }
            }
            .onChange(of: groups.count) { _ in
                initialNewGroupName = getNextGroupName()
            }
            .onAppear {
                initialNewGroupName = getNextGroupName()
            }
    }
    
    @MainActor @ViewBuilder
    private func createFolderSheetView() -> some View {
        CreateGroupSheetView(
            name: $initialNewGroupName,
            createType: .group
        ) { name in
            Task {
                do {
                    try await fileState.createNewGroup(
                        name: name,
                        activate: true,
                        parentGroupID: parentGroupID,
                        context: viewContext,
                        animation: .smooth
                    )
                    
                } catch {
                    alertToast(error)
                }
            }
        }
        .controlSize(.large)
    }
    
    func getNextGroupName() -> String {
        let name = String(localizable: .sidebarGroupListCreateNewGroupNamePlaceholder)
        var result = name
        var i = 1
        while groups.first(where: {$0.name == result}) != nil {
            result = "\(name) \(i)"
            i += 1
        }
        return result
    }
}

struct CreateGroupSheetView: View {
    @Environment(\.containerHorizontalSizeClass) private var containerHorizontalSizeClass

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
    
    @FocusState private var isFieldFocused: Bool
    
    var body: some View {
        if #available(macOS 13.0, *) {
#if os(iOS)
            if containerHorizontalSizeClass == .compact {
                NavigationStack {
                    content()
                }
            } else {
                content()
            }
#else
            content()
#endif
        } else {
            content()
                .frame(width: 400)
        }
    }
    

    @MainActor @ViewBuilder
    private func content() -> some View {
        Form {
            Section {
                HStack {
                    Text(.localizable(.sidebarGroupListCreateGroupName))
#if os(macOS)
                        .frame(width: 40, alignment: .trailing)
#endif
                    TextField("", text: $name, prompt: Text("My new group"))
                        .focused($isFieldFocused)
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
                if containerHorizontalSizeClass == .regular {
                    Text(
                        createType == .group
                        ? .localizable(.sidebarGroupListCreateTitle)
                        : .localizable(.sidebarGroupListCreateFolderTitle)
                    )
                    .fontWeight(.bold)
                }
            } footer: {
                if containerHorizontalSizeClass == .regular {
                    HStack {
                        Spacer()
                        Button(.localizable(.sidebarGroupListCreateButtonCancel)) { dismiss() }
                        Button(.localizable(.sidebarGroupListCreateButtonCreate)) {
                            onCreate(name)
                            dismiss()
                        }
                        .modifier(ProminentButtonModifier())
                        .disabled(name.isEmpty)
                    }
                }
            }
        }
        .labelsHidden()
#if os(macOS)
        .padding()
#else
        .navigationTitle(
            createType == .group
            ? .localizable(.sidebarGroupListCreateTitle)
            : .localizable(.sidebarGroupListCreateFolderTitle)
        )
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                if containerHorizontalSizeClass == .compact {
                    ToolbarDismissButton()
                }
            }
            
            ToolbarItem(placement: .topBarTrailing) {
                if containerHorizontalSizeClass == .compact {
                    ToolbarDoneButton {
                        onCreate(name)
                        dismiss()
                    }
                    .disabled(name.isEmpty)
                }
            }
        }
#endif
        .onAppear {
            isFieldFocused = true
        }
    }
}


#Preview {
    CreateGroupSheetView(name: .constant(""), createType: .group) { newName in
        
    }
}
