//
//  FileListView.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 2023/1/4.
//

import SwiftUI

import ChocofordUI

struct FileListView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.alertToast) var alertToast
    @EnvironmentObject var fileState: FileState
    

    @FetchRequest
    private var files: FetchedResults<File>
    
    init(currentGroupID: Group.ID, groupType: Group.GroupType?) {
        self._files = FetchRequest<File>(
            sortDescriptors: [
                SortDescriptor(\.updatedAt, order: .reverse),
                SortDescriptor(\.createdAt, order: .reverse)
            ],
            predicate: groupType == .trash ? NSPredicate(
                format: "inTrash == YES"
            ) : NSPredicate(
                format: "group.id == %@ AND inTrash == NO", (currentGroupID ?? UUID()) as CVarArg
            ),
            animation: .smooth
        )
    }
    

    
    struct DateGrouppedFiles {
        var date: Date
        var files: [File]
    }
    
    @State private var isFirstAppear = true
    
    var body: some View {
        ZStack {
            if #available(macOS 14.0, iOS 17.0, *) {
                content()
                    .onChange(of: fileState.currentGroup) { oldValue, newValue in
                        if fileState.currentFile?.group != newValue || fileState.currentFile?.inTrash != (newValue?.groupType == .trash) {
                            if horizontalSizeClass == .compact {
                                // do not set file at iphone.
                                return
                            }
                            fileState.currentFile = files.first
                        }
                    }
                    .onChange(of: fileState.currentFile) { _, newValue in
                        if newValue == nil {
                            if let file = files.first {
                                if horizontalSizeClass == .regular {
                                    fileState.currentFile = file
                                }
                            } else {
                                do {
                                    try fileState.createNewFile()
                                } catch {
                                    alertToast(error)
                                }
                            }
                        }
                    }
                    .onChange(of: files) { _, newValue in
                        if newValue.isEmpty, horizontalSizeClass == .compact {
                            do {
                                try fileState.createNewFile(active: false)
                            } catch {
                                alertToast(error)
                            }
                        }
                    }
            } else {
                content()
                    .onChange(of: fileState.currentGroup) { newValue in
                        if fileState.currentFile?.group != newValue || fileState.currentFile?.inTrash != (newValue?.groupType == .trash) {
                            if horizontalSizeClass == .compact {
                                return
                            }
                            fileState.currentFile = files.first
                        }
                    }
                    .onChange(of: fileState.currentFile) { newValue in
                        if newValue == nil {
                            if let file = files.first {
                                if horizontalSizeClass == .regular {
                                    fileState.currentFile = file
                                }
                            } else {
                                do {
                                    try fileState.createNewFile()
                                } catch {
                                    alertToast(error)
                                }
                            }
                        }
                    }
                
                .onChange(of: files) { newValue in
                    if newValue.isEmpty, horizontalSizeClass == .compact {
                        do {
                            try fileState.createNewFile(active: false)
                        } catch {
                            alertToast(error)
                        }
                    }
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .didImportToExcalidrawZ)) { notification in
            guard let fileID = notification.object as? UUID else { return }
            if let file = files.first(where: {$0.id == fileID}) {
                fileState.currentFile = file
            }
        }
        .onAppear {
            defer { isFirstAppear = false }
            guard fileState.currentFile == nil else { return }
            if files.isEmpty {
                do {
                    try fileState.createNewFile()
                } catch {
                    alertToast(error)
                }
            } else if horizontalSizeClass == .regular || isFirstAppear {
                fileState.currentFile = files.first
            }
        }
    }
    
    
    @MainActor @ViewBuilder
    private func content() -> some View {
        ScrollView {
            LazyVStack(alignment: .leading) {
                ForEach(files) { file in
                    FileRowView(file: file)
                        .transition(.opacity)
                }
            }
            // ⬇️ cause `com.apple.SwiftUI.AsyncRenderer (22): EXC_BREAKPOINT` on iOS
            // .animation(.smooth, value: files)
            .padding(.horizontal, 8)
            .padding(.vertical, 12)
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
