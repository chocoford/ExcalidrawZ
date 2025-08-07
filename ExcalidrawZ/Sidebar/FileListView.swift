//
//  FileListView.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 2023/1/4.
//

import SwiftUI
import CoreData

import ChocofordUI

struct FileListView: View {
    @Environment(\.managedObjectContext) private var managedObjectContext
    @Environment(\.containerHorizontalSizeClass) private var containerHorizontalSizeClass
    @Environment(\.uiSizeClass) private var uiSizeClass
    @Environment(\.alertToast) var alertToast
    @EnvironmentObject var fileState: FileState
    
    var sortField: ExcalidrawFileSortField
    @FetchRequest
    private var files: FetchedResults<File>
    
    init(
        currentGroupID: Group.ID,
        groupType: Group.GroupType?,
        sortField: ExcalidrawFileSortField
    ) {
        let sortDescriptors: [SortDescriptor<File>] = {
            switch sortField {
                case .updatedAt:
                    [
                        SortDescriptor(\.updatedAt, order: .reverse),
                        SortDescriptor(\.createdAt, order: .reverse)
                    ]
                case .name:
                    [
                        SortDescriptor(\.updatedAt, order: .reverse),
                        SortDescriptor(\.createdAt, order: .reverse),
                        SortDescriptor(\.name, order: .reverse),
                    ]
                case .rank:
                    [
                        SortDescriptor(\.updatedAt, order: .reverse),
                        SortDescriptor(\.createdAt, order: .reverse),
                        SortDescriptor(\.rank, order: .forward),
                    ]
            }
        }()
        self.sortField = sortField
        self._files = FetchRequest<File>(
            sortDescriptors: sortDescriptors,
            predicate: groupType == .trash ? NSPredicate(
                format: "inTrash == YES"
            ) : NSPredicate(
                format: "group.id == %@ AND inTrash == NO", (currentGroupID ?? UUID()) as CVarArg
            ),
            animation: .smooth
        )
    }
    
    @State private var fileIDToBeRenamed: NSManagedObjectID?
    var fileToBeRenamed: File? {
        guard let fileIDToBeRenamed else { return nil }
        return managedObjectContext.object(with: fileIDToBeRenamed) as? File
    }

    struct DateGrouppedFiles {
        var date: Date
        var files: [File]
    }
    
    
    var body: some View {
        ZStack {
            if #available(macOS 14.0, iOS 17.0, *) {
                content()
                    .onChange(of: fileState.currentGroup) { oldValue, newValue in
                        onCurrentGroupChanged(newValue)
                    }
                    .onChange(of: fileState.currentFile) { _, newValue in
                        onCurrentFileChanged(newValue)
                    }
                    .onChange(of: files) { _, newValue in
                        onFilesChanged(newValue)
                    }
            } else {
                content()
                    .onChange(of: fileState.currentGroup) { newValue in
                        onCurrentGroupChanged(newValue)
                    }
                    .onChange(of: fileState.currentFile) { newValue in
                        onCurrentFileChanged(newValue)
                    }
                    .onChange(of: files) { newValue in
                        onFilesChanged(newValue)
                    }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .didImportToExcalidrawZ)) { notification in
            guard let fileID = notification.object as? UUID else { return }
            if let file = files.first(where: {$0.id == fileID}) {
                fileState.currentActiveFile = .file(file)
            }
        }
        .onAppear {
            guard fileState.currentFile == nil else { return }
            if files.isEmpty {
                do {
                    try fileState.createNewFile(context: managedObjectContext)
                } catch {
                    alertToast(error)
                }
            } else if containerHorizontalSizeClass != .compact {
                if let file = files.first {
                    fileState.currentActiveFile = .file(file)
                }
            }
        }
    }
    
    
    @MainActor @ViewBuilder
    private func content() -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 10) {
                // `id: \.self` - Prevent crashes caused by closing the Share Sheet that was opened from the app menu.
                // MultiThread access
                ForEach(files, id: \.self) { file in
                    FileRowView(
                        file: file,
                        sortField: sortField
                    )
                }
            }
            // ⬇️ cause `com.apple.SwiftUI.AsyncRenderer (22): EXC_BREAKPOINT` on iOS
            // .animation(.smooth, value: files)
            .padding(.horizontal, 8)
            .padding(.vertical, 12)
            .fileListDropFallback()
#if os(macOS)
            .background {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if NSEvent.modifierFlags.contains(.command) || NSEvent.modifierFlags.contains(.shift) {
                            return
                        }
                        fileState.resetSelections()
                    }
            }
#endif
        }
    }
    
    private func onCurrentGroupChanged(_ newValue: Group?) {
        guard newValue != nil else { return }
        if fileState.currentFile?.group != newValue || fileState.currentFile?.inTrash != (newValue?.groupType == .trash) {
            if containerHorizontalSizeClass == .compact {
                // do not set file at iphone.
                return
            }
            fileState.currentFile = files.first
        }
    }
    
    private func onCurrentFileChanged(_ newValue: File?) {
//        guard fileState.currentGroup != nil else { return }
//        if newValue == nil {
//            if let file = files.first {
//                if containerHorizontalSizeClass != .compact {
//                    fileState.currentFile = file
//                }
//            } else {
//                do {
//                    try fileState.createNewFile(active: true, context: managedObjectContext)
//                } catch {
//                    alertToast(error)
//                }
//            }
//        }
    }
    
    private func onFilesChanged(_ newValue: FetchedResults<File>) {
        if newValue.isEmpty, containerHorizontalSizeClass == .compact {
            do {
                try fileState.createNewFile(active: false, context: managedObjectContext)
            } catch {
                alertToast(error)
            }
        } else if !newValue.contains(where: {$0.id == fileState.currentFile?.id}),
                  containerHorizontalSizeClass != .compact {
            fileState.currentFile = newValue.first
        }
    }
}

extension FileListView {
    @ToolbarContentBuilder
    private func toolbarContent() -> some ToolbarContent {
        ToolbarItemGroup(placement: .principal) {
            Button {
                
            } label: {
                Image(systemSymbol: .trash)
            }
        }
    }
}


#if DEBUG
//struct FileListView_Previews: PreviewProvider {
//    static var previews: some View {
//        FileListView(
//            store: .init(
//                initialState: .init(state: .init())
//            ) {
//                FileStore()
//            }
//        )
//        .frame(width: 200)
//    }
//}
#endif
