//
//  LocalFoldersListView.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 2/21/25.
//

import SwiftUI
import SwiftyAlert
import CoreData
import Observation

import ChocofordUI
#if os(macOS)
import FSEventsWrapper
#endif


struct LocalFoldersListView: View {
    var showFiles: Bool
    
    init(
        showFiles: Bool = true
    ) {
        self.showFiles = showFiles
    }

    var body: some View {
        LocalFoldersProvider { folders in
            LocalFoldersListContent(
                folders: folders,
                showFiles: showFiles,
                showsEmptyPlaceholder: true
            )
        }
    }
}

struct LocalFoldersListContent: View {
    @AppStorage("ShowLocalFolderEmptyPlaceholder") private var showLocalFolderEmptyPlaceholder = true

    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.alertToast) private var alertToast
    @Environment(FileState.self) private var fileState

    let folders: FetchedResults<LocalFolder>
    let showFiles: Bool
    let showsEmptyPlaceholder: Bool

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(folders, id: \.sidebarGroupScrollTarget) { folder in
                Section {
                    LocalFoldersView(
                        folder: folder,
                        sortField: fileState.sortField,
                        showFiles: showFiles
                    ) {
                        fileState.selectNeighborAfterRemovingLocalFolder(folder, from: folders)
                    }
                }
            }

            if showsEmptyPlaceholder,
               showLocalFolderEmptyPlaceholder,
               folders.isEmpty,
               showFiles {
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
                    .transition(.scale(scale: 0, anchor: .topTrailing).combined(with: .opacity))
            }
        }
        .modifier(LocalFolderSidebarExpansionModifier())
        .animation(.smooth, value: showLocalFolderEmptyPlaceholder)
#if DEBUG
        .onAppear { showLocalFolderEmptyPlaceholder = true }
#endif
    }
}

struct LocalFolderSidebarExpansionModifier: ViewModifier {
    @Environment(\.sidebarFileReveal) private var sidebarFileReveal
    @State private var expansion = LocalFolderSidebarExpansionState()

    func body(content: Content) -> some View {
        content
            .environment(expansion)
            .watch(value: sidebarFileReveal, initial: true) { reveal in
                guard let reveal, case .localFile = reveal.file else { return }
                withAnimation(.smooth(duration: 0.2)) {
                    for case .localFolder(let id) in reveal.folders {
                        expansion.setExpanded(true, for: id)
                    }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .shouldExpandGroup)) { notification in
                guard let objectID = notification.object as? NSManagedObjectID,
                      objectID.entity.name == "LocalFolder" else { return }
                withAnimation(.smooth(duration: 0.2)) {
                    expansion.setExpanded(true, for: objectID)
                }
            }
    }
}

@MainActor
extension FileState {
    func selectNeighborAfterRemovingLocalFolder(_ folder: LocalFolder, from folders: some RandomAccessCollection<LocalFolder>) {
        guard currentActiveGroup == .localFolder(folder),
              let index = folders.firstIndex(of: folder) else { return }
        let neighbor = index == folders.startIndex
            ? folders.dropFirst().first
            : folders.first
        currentActiveGroup = neighbor.map(ActiveGroup.localFolder)
    }
}

/// Expansion belongs to the list so offscreen lazy rows can receive navigation
/// requests and retain their state when SwiftUI releases their view storage.
@MainActor @Observable
final class LocalFolderSidebarExpansionState {
    private var expandedIDs: Set<NSManagedObjectID> = []

    func isExpanded(_ objectID: NSManagedObjectID) -> Bool {
        expandedIDs.contains(objectID)
    }

    func setExpanded(_ expanded: Bool, for objectID: NSManagedObjectID) {
        guard isExpanded(objectID) != expanded else { return }
        if expanded { expandedIDs.insert(objectID) }
        else { expandedIDs.remove(objectID) }
    }
}


struct LocalFolderEmptyPlaceholderView: View {
    @Environment(\.containerHorizontalSizeClass) private var containerHorizontalSizeClass
    @AppStorage("ShowLocalFolderEmptyPlaceholder") private var showLocalFolderEmptyPlaceholder: Bool = true

    var body: some View {
        VStack(spacing: 12) {
            Image(systemSymbol: .folder)
                .font(.system(size: 30))
                .foregroundStyle(.secondary)
            
            Text(localizable: .sidebarLocalFolderEmptyPlaceholder)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            VStack(spacing: 6) {
                ImportLocalFolderButton()
                    .font(.footnote)
                    .modernButtonStyle(style: .glassProminent, shape: .modern)
                
                if containerHorizontalSizeClass == .compact {
                    Button {
                        showLocalFolderEmptyPlaceholder = false
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemSymbol: .xmark)
                            Text(localizable: .generalButtonClose)
                        }
                    }
                    .font(.footnote)
                    .modernButtonStyle(style: .glass, shape: .modern)
                }
            }
        }
        .padding(.vertical, 24)
        .frame(maxWidth: .infinity)
        .overlay(alignment: .topLeading) {
            if containerHorizontalSizeClass != .compact {
                Button {
                    showLocalFolderEmptyPlaceholder = false
                } label: {
                    Image(systemSymbol: .xmark)
                        .foregroundStyle(.secondary)
                }
                .modernButtonStyle(style: .borderless)
                .padding()
            }
        }
    }
}
