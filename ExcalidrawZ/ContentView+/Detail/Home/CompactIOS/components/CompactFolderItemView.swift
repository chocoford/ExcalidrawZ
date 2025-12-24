//
//  CompactFolderItemView.swift
//  ExcalidrawZ
//
//  Created by Chocoford on 12/19/25.
//

import SwiftUI
import CoreData
import SFSafeSymbols

#if os(iOS)
struct CompactFolderItemView: View {
    @Environment(\.editMode) private var editMode
    @EnvironmentObject private var fileState: FileState
    @EnvironmentObject private var layoutState: LayoutState
    
    var objectID: NSManagedObjectID
    var name: String
    var type: Group.GroupType
    var itemsCount: Int
    
    init<HomeGroup: ExcalidrawGroup>(group: HomeGroup) {
        self.objectID = group.objectID
        self.name = group.name ?? String(localizable: .generalUntitled)
        self.type = group.groupType
        self.itemsCount = group.filesCount + group.subgroupsCount
    }

    init(
        objectID: NSManagedObjectID,
        name: String,
        type: Group.GroupType = .default,
        itemsCount: Int,
    ) {
        self.objectID = objectID
        self.name = name
        self.type = type
        self.itemsCount = itemsCount
    }
    
    var isSelected: Bool {
        fileState.selectedGroups.contains(objectID)
    }
    
    var layout: AnyLayout {
        switch layoutState.compactBrowserLayout {
            case .grid:
                AnyLayout(VStackLayout(alignment: .center, spacing: 8))
            case .list:
                AnyLayout(HStackLayout(alignment: .center, spacing: 8))
        }
    }

    var body: some View {
        layout {
            // Folder icon area
            Image(systemSymbol: type == .trash ? .trashFill : .folderFill)
                .resizable()
                .scaledToFit()
                .foregroundStyle(Color.accentColor)
                .padding(10)
                .frame(
                    width: layoutState.compactBrowserLayout == .grid ? nil : 80,
                    height: layoutState.compactBrowserLayout == .grid ? 80 : nil,
                )
                .frame(maxWidth: layoutState.compactBrowserLayout == .grid ? .infinity : nil)

            // Folder info
            VStack(
                alignment: layoutState.compactBrowserLayout == .grid ? .center : .leading,
                spacing: 2
            ) {
                Text(name)
                    .font(layoutState.compactBrowserLayout == .grid ? .caption : .body)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(
                        maxWidth: .infinity,
                        alignment: layoutState.compactBrowserLayout == .grid ? .center : .leading
                    )

                Text("\(itemsCount) items")
                    .font(layoutState.compactBrowserLayout == .grid ? .caption2 : .footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 4)
            
            if layoutState.compactBrowserLayout == .list {
                Spacer(minLength: 0)
            }
        }
        .opacity(editMode?.wrappedValue.isEditing == true ? 0.7 : 1.0)
        .overlay(alignment: .center) {
            if editMode?.wrappedValue.isEditing == true {
                Circle()
                    .stroke(.white)
                    .frame(width: 20, height: 20)
                    .background {
                        if #available(iOS 26.0, *) {
                            Image(systemSymbol: .checkmarkCircleFill)
                                .resizable()
                                .scaledToFit()
                                .symbolRenderingMode(.multicolor)
                                .symbolEffect(.drawOn, options: .speed(2), isActive: !isSelected)
                        } else {
                            Image(systemSymbol: .checkmarkCircleFill)
                                .resizable()
                                .scaledToFit()
                                .opacity(isSelected ? 1 : 0)
                                .animation(.default, value: isSelected)
                        }
                    }
            }
        }
        .simultaneousGesture(TapGesture().onEnded { _ in
            fileState.selectedGroups.insertOrRemove(self.objectID)
        }, isEnabled: editMode?.wrappedValue.isEditing == true)
        .animation(.smooth, value: layoutState.compactBrowserLayout)
    }
}


private struct CompactFolderItemPreviewView: View {
    @State private var editMode = EditMode.inactive
    
    var body: some View {
        NavigationStack {
            LazyVGrid(columns: [
                GridItem(.adaptive(minimum: 120), spacing: 12)
            ], spacing: 12) {
                CompactFolderItemView(
                    objectID: .init(),
                    name: "Documents",
                    itemsCount: 24,
                )
                
                CompactFolderItemView(
                    objectID: .init(),
                    name: "Photos",
                    itemsCount: 156,
                )
                
                CompactFolderItemView(
                    objectID: .init(),
                    name: "Very Long Folder Name That Might Wrap",
                    itemsCount: 5,
                )
            }
            .environment(\.editMode, $editMode)
            .padding()
            .toolbar {
                if !editMode.isEditing {
                    Button {
                        editMode = .active
                    } label: {
                        Image(systemSymbol: .checkmarkCircle)
                    }
                } else {
                    Button {
                        editMode = .inactive
                    } label: {
                        Label(.localizable(.generalButtonDone), systemSymbol: .checkmark)
                            .labelStyle(.iconOnly)
                    }
                    .modernButtonStyle(style: .glassProminent)
                }
            }
        }
        .environmentObject(FileState())
    }
}

#Preview {
    CompactFolderItemPreviewView()
}
#endif
