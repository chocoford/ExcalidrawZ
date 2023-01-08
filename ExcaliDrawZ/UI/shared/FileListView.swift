//
//  FileListView.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 2023/1/4.
//

import SwiftUI

struct FileListView: View {
    @EnvironmentObject var store: AppStore
//    @FetchRequest(sortDescriptors: [SortDescriptor(\.createdAt, order: .reverse)],
//                  predicate: group != nil ? NSPredicate(format: "group == %@", group!) : NSPredicate(value: false))
//                  animation: .easeIn)
    @FetchRequest var files: FetchedResults<File>
    
    init(group: Group?) {
        self._files = FetchRequest<File>(sortDescriptors: [SortDescriptor(\.createdAt, order: .reverse)],
                                   predicate: group != nil ? NSPredicate(format: "group == %@", group!) : NSPredicate(value: false))
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
//        .onChange(of: store.state.currentGroup) { newValue in
//            if let group = newValue {
//                files.nsPredicate = .init(format: "group == %@", group)
//            }
//            dump(files)
//        }
        .animation(.easeIn, value: files)
    }
}

struct FileListView_Previews: PreviewProvider {
    static var previews: some View {
        FileListView(group: nil)
    }
}

