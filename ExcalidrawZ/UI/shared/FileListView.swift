//
//  FileListView.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 2023/1/4.
//

import SwiftUI

struct FileListView: View {
    @EnvironmentObject var store: AppStore
    @FetchRequest var files: FetchedResults<File>
    
    init(group: Group?) {
        let predicate: NSPredicate
        
        if let group = group {
            if group.groupType == .trash {
                predicate = NSPredicate(format: "inTrash == YES")
            } else {
                predicate = NSPredicate(format: "group == %@ AND inTrash == NO", group)
            }
        } else {
            predicate = NSPredicate(value: false)
        }
                
        self._files = FetchRequest<File>(sortDescriptors: [ SortDescriptor(\.updatedAt, order: .reverse),
                                                            SortDescriptor(\.createdAt, order: .reverse)],
                                   predicate: predicate)
    }
    
    private var selectedFile: Binding<File?> {
        store.binding(for: \.currentFile) {
            return .setCurrentFile($0)
        }
    }
    
    var body: some View {
        List(files, id: \.id, selection: selectedFile) { file in
            FileRowView(fileInfo: file)
        }
        .listStyle(.sidebar)
        .animation(.easeIn, value: files)
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
struct FileListView_Previews: PreviewProvider {
    static var previews: some View {
        FileListView(group: nil)
            .environmentObject(AppStore.preview)
    }
}
#endif
