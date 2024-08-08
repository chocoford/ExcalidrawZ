//
//  FileListView.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 2023/1/4.
//

import SwiftUI

import ChocofordUI

struct FileListView: View {
    @EnvironmentObject var fileState: FileState
    
    var groups: FetchedResults<Group>
    
    init(groups: FetchedResults<Group>, currentGroup: Group) {
        self.groups = groups
        self._files = FetchRequest<File>(
            sortDescriptors: [
                SortDescriptor(\.updatedAt, order: .reverse),
                SortDescriptor(\.createdAt, order: .reverse)
            ],
            predicate: NSPredicate(
                format: "group == %@", currentGroup
            )
        )
    }
    
    @FetchRequest
    private var files: FetchedResults<File>
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading) {
                ForEach(files) { file in
                    FileRowView(groups: groups, file: file)
                        .transition(.opacity)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 12)
        }
        .watchImmediately(of: fileState.currentGroup) { newValue in
            if newValue != nil {
//                self.store.send(.fetchFiles)
            }
        }
//            .watchImmediately(of: viewStore.group) { group in
//                guard let group = group else { return }
//                if group.groupType == .trash {
//                    fileList.nsPredicate = NSPredicate(format: "inTrash == YES")
//                } else {
//                    fileList.nsPredicate = NSPredicate(format: "group == %@ AND inTrash == NO", group)
//                }
//            }
//            .watchImmediately(of: fileList) { newValue in
//                print("fileList did changed")
//                viewStore.send(.syncFiles(newValue))
//            }
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
