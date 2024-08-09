//
//  FileListView.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 2023/1/4.
//

import SwiftUI

import ChocofordUI

struct FileListView: View {
    @Environment(\.alertToast) var alertToast
    @EnvironmentObject var fileState: FileState
    
    var groups: FetchedResults<Group>
    
    init(groups: FetchedResults<Group>, currentGroup: Group) {
        self.groups = groups
        self._files = FetchRequest<File>(
            sortDescriptors: [
                SortDescriptor(\.updatedAt, order: .reverse),
                SortDescriptor(\.createdAt, order: .reverse)
            ],
            predicate: currentGroup.groupType == .trash ? NSPredicate(
                format: "inTrash == YES", currentGroup
            ) : NSPredicate(
                format: "group == %@ AND inTrash == NO", currentGroup
            ),
            animation: .smooth
        )
    }
    
    @FetchRequest
    private var files: FetchedResults<File>
    
    
    struct DateGrouppedFiles {
        var date: Date
        var files: [File]
    }
//    var dateGrouppedFiles: [DateGrouppedFiles] {
//        
//    }
    
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading) {
                ForEach(files) { file in
                    FileRowView(groups: groups, file: file)
                        .transition(.opacity)
                }
            }
            .animation(.smooth, value: files)
            .padding(.horizontal, 8)
            .padding(.vertical, 12)
        }
        .watchImmediately(of: fileState.currentGroup) { newValue in
            if fileState.currentFile?.group != newValue || fileState.currentFile?.inTrash != (newValue?.groupType == .trash) {
                fileState.currentFile = files.first
            }
        }
        .onChange(of: fileState.currentFile) { oldValue, newValue in
            if newValue == nil {
                if let file = files.first {
                    fileState.currentFile = file
                } else {
                    do {
                        try fileState.createNewFile()
                    } catch {
                        alertToast(error)
                    }
                }
            }
        }
    }
}

extension FileListView {
    @ToolbarContentBuilder private func toolbarContent() -> some ToolbarContent {
        ToolbarItemGroup(placement: .principal) {
            Button {
                
            } label: {
                Image(systemName: "trash")
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
