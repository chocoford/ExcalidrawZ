//
//  GroupRowView.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 2023/1/10.
//

import SwiftUI
import ChocofordUI
import CoreData

struct GroupRowView: View {
    @AppStorage("FolderStructureStyle") var folderStructStyle: FolderStructureStyle = .disclosureGroup

    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.alertToast) var alertToast
    @EnvironmentObject var fileState: FileState
    
    @FetchRequest(
        sortDescriptors: [],
        predicate: NSPredicate(format: "parent = nil"),
        animation: .default
    )
    private var topLevelGroups: FetchedResults<Group>
    
    var group: Group
    @Binding var isExpanded: Bool
    var isSelected: Bool
    @Binding var isBeingDropped: Bool
    
    /// Tap to select is move to parent view -- GroupsView
    /// in system above macOS 13.0.
    init(
        group: Group,
        isSelected: Bool,
        isExpanded: Binding<Bool>,
        isBeingDropped: Binding<Bool>
    ) {
        self.group = group
        self.isSelected = isSelected
        self._isExpanded = isExpanded
        self._isBeingDropped = isBeingDropped
    }

    var body: some View {
        if group.groupType != .trash {
            if #available(macOS 13.0, *) {
                content
//                    .dropDestination(for: FileLocalizable.self) { fileInfos, location in
//                        guard let _ = fileInfos.first else { return false }
//                        return true
//                    }
            } else {
                content
            }
        } else {
            content
        }
    }

    @MainActor @ViewBuilder
    private var content: some View {
        groupRowView()
            .modifier(
                GroupContextMenuViewModifier(
                    group: group,
                    folderStructStyle: folderStructStyle,
                    isExpanded: $isExpanded
                )
            )
            .modifier(
                GroupRowDragDropModifier(
                    group: group,
                    shouldHighlight: $isBeingDropped
                )
            )
    }

    @MainActor @ViewBuilder
    private func groupRowView() -> some View {
        if folderStructStyle == .disclosureGroup {
            HStack(spacing: 6) {
                groupIcon
                Text(group.name ?? String(localizable: .generalUntitled)).lineLimit(1)
                Spacer()
            }
            .contentShape(Rectangle())
        } else {
            Button {
                fileState.currentActiveGroup = .group(group)
                fileState.currentActiveFile = nil
            } label: {
                HStack(spacing: 6) {
                    groupIcon
                    Text(group.name ?? String(localizable: .generalUntitled)).lineLimit(1)
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.excalidrawSidebarRow(isSelected: isSelected, isMultiSelected: false))
        }
    }
    
    @MainActor @ViewBuilder
    private var groupIcon: some View {
        HStack {
            switch group.groupType {
                case .`default`:
                    Image(systemSymbol: .folder)
                case .trash:
                    Image(systemSymbol: .trash)
                case .normal:
                    Image(systemSymbol: .init(rawValue: group.icon ?? "folder"))
            }
        }
        .frame(width: 20, alignment: .center)
    }
}

