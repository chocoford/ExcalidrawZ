//
//  LocalFolderRowView.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 3/3/25.
//

import SwiftUI
import CoreData

import ChocofordUI

struct LocalFolderRowView: View {
    @AppStorage("FolderStructureStyle") var folderStructStyle: FolderStructureStyle = .disclosureGroup

    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.alertToast) private var alertToast
    @EnvironmentObject private var fileState: FileState
    @EnvironmentObject private var localFolderState: LocalFolderState

    var folder: LocalFolder
    // @Binding var isBeingDropped: Bool

    var onDelete: () -> Void
    
    init(
        folder: LocalFolder,
        // isBeingDropped: Binding<Bool>,
        onDelete: @escaping () -> Void
    ) {
        self.folder = folder
        // self._isBeingDropped = isBeingDropped
        self.onDelete = onDelete
    }
    

    var isSelected: Bool {
        if case .localFolder(let folder) = fileState.currentActiveGroup {
            return self.folder == folder
        } else {
            return false
        }
    }

    var body: some View {
        content()
    }

    @MainActor @ViewBuilder
    private func content() -> some View {
        if folderStructStyle == .disclosureGroup {
            HStack(spacing: 6) {
                Image(systemSymbol: .folderFill)
                    .foregroundStyle(Color(red: 12/255.0, green: 157/255.0, blue: 229/255.0))
                Text(folder.url?.lastPathComponent ?? String(localizable: .generalUnknown))
            }
            .lineLimit(1)
            .truncationMode(.middle)
            .contentShape(Rectangle())
        } else {
            Button {
                fileState.currentActiveGroup = .localFolder(folder)
                fileState.currentActiveFile = nil
            } label: {
                HStack(spacing: 6) {
                    Image(systemSymbol: .folderFill)
                        .foregroundStyle(Color(red: 12/255.0, green: 157/255.0, blue: 229/255.0))
                    Text(folder.url?.lastPathComponent ?? String(localizable: .generalUnknown))
                }
                .lineLimit(1)
                .truncationMode(.middle)
                .contentShape(Rectangle())
            }
            .buttonStyle(.excalidrawSidebarRow(isSelected: isSelected, isMultiSelected: false))
        }
    }
    
}
