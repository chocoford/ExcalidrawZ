//
//  LocalFoldersListView.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 2/21/25.
//

import SwiftUI
import CoreData

import ChocofordUI
#if os(macOS)
import FSEventsWrapper
#endif


struct LocalFoldersListView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.alertToast) private var alertToast

    @EnvironmentObject private var fileState: FileState
    
    var showFiles: Bool
    
    init(
        showFiles: Bool = true
    ) {
        self.showFiles = showFiles
    }

    var body: some View {
        LocalFoldersProvider { folders in
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(folders) { folder in
                    VStack(alignment: .leading, spacing: 0) {
                        // Local folder view
                        Section {
                            LocalFoldersView(
                                folder: folder,
                                sortField: fileState.sortField,
                                showFiles: showFiles
                            ) {
                                // switch current folder first if necessary.
                                if case .localFolder(let localFolder) = fileState.currentActiveGroup,
                                   localFolder == folder {
                                    guard let index = folders.firstIndex(of: folder) else {
                                        return
                                    }
                                    if index == 0 {
                                        if folders.count > 1 {
                                            fileState.currentActiveGroup = .localFolder(folders[1])
                                        } else {
                                            fileState.currentActiveGroup = nil
                                        }
                                    } else {
                                        fileState.currentActiveGroup = .localFolder(folders[0])
                                    }
                                }
                            }
                        }
                    }
                }
                
                if folders.isEmpty, showFiles {
                    LocalFolderEmptyPlaceholderView()
                        .background {
                            ZStack {
                                RoundedRectangle(cornerRadius: 20)
                                    .fill(.regularMaterial)
                                RoundedRectangle(cornerRadius: 20)
                                    .stroke(.secondary, lineWidth: 0.5)
                            }
                        }
                        .padding(.vertical, 10)
                }
            }
            .onAppear {
                for i in 0..<folders.count {
                    do {
                        try folders[i].refreshChildren(context: viewContext)
                    } catch {
                        alertToast(error)
                    }
                }
            }
        }
    }
    
}


struct LocalFolderEmptyPlaceholderView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemSymbol: .folder)
                .font(.system(size: 30))
                .foregroundStyle(.secondary)
            
            Text("Local folders allow you to reference and work with Excalidraw files stored on your disk.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            HStack(spacing: 6) {
                ImportLocalFolderButton()
                    .font(.footnote)
                    .modernButtonStyle(style: .glassProminent, shape: .modern)
            }
        }
        .padding(.vertical, 24)
        .frame(maxWidth: .infinity)

    }
}
