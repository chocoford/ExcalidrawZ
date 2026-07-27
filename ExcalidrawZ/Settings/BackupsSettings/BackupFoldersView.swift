//
//  BackupFoldersView.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 2/28/25.
//

import SwiftUI

import ChocofordUI

private struct BackupFolderItem: Hashable, Sendable {
    let url: URL
    let isDirectory: Bool
    let isEncrypted: Bool
}

struct BackupFoldersView: View {
    @Environment(\.alertToast) private var alertToast
    
    @Binding var selection: URL?
    
    var folder: URL
    var depth: Int
    
    init(
        selection: Binding<URL?>,
        folder: URL,
        depth: Int = 0
    ) {
        self._selection = selection
        self.folder = folder
        self.depth = depth
    }
    
    @State private var content: [BackupFolderItem] = []
    
    var body: some View {
        TreeStructureView(children: content, id: \.url, paddingLeading: 6, usesLazyChildren: false) {
            HStack(spacing: 4) {
                let folderName = folder.lastPathComponent
                Label(
                    folderName,
                    systemSymbol: depth == 0 ? (folderName == "Cloud" ? .cloud : (folderName == "Local" ? .externaldrive : .folder)) : .folder
                )
                // .symbolVariant(.fill)
                .lineLimit(1)
                .truncationMode(.middle)
                
                Spacer()
            }
            .padding(6)
        } childView: { item in
            if item.isDirectory {
                BackupFoldersView(selection: $selection, folder: item.url, depth: depth + 1)
            } else if let name = (try? item.url.resourceValues(forKeys: [.nameKey]))?.name,
                      name.hasSuffix(".excalidraw") {
                Button {
                    selection = item.url
                } label: {
                    HStack(spacing: 4) {
                        Label(
                            item.url.deletingPathExtension().lastPathComponent,
                            systemImage: item.iconSystemName
                        )
                            // .symbolVariant(.fill)
                            // .padding(.leading, CGFloat(8 * depth) + 14)
                    }
                    .lineLimit(1)
                    .truncationMode(.tail)
                }
                .buttonStyle(
                    .excalidrawSidebarRow(isSelected: selection == item.url, isMultiSelected: false)
                )
            }
        }
        .task(id: folder) {
            await loadContent()
        }
    }

    @MainActor
    private func loadContent() async {
        do {
            let folderURL = folder
            let loadedContent = try await Task.detached(priority: .utility) {
                try Self.loadFolderContent(from: folderURL)
            }.value
            guard !Task.isCancelled else {
                return
            }
            self.content = loadedContent
        } catch {
            alertToast(error)
        }
    }

    private nonisolated static func loadFolderContent(
        from folder: URL
    ) throws -> [BackupFolderItem] {
        try FileManager.default.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: [.nameKey, .isDirectoryKey],
            options: .skipsHiddenFiles
        )
        .compactMap { url in
            let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
            guard isDirectory || url.pathExtension == "excalidraw" else {
                return nil
            }
            return BackupFolderItem(
                url: url,
                isDirectory: isDirectory,
                isEncrypted: false
            )
        }
    }
}

private extension BackupFolderItem {
    var iconSystemName: String {
        guard isEncrypted else { return "doc" }
        if #available(macOS 15.0, iOS 18.0, *) {
            return "lock.document"
        } else {
            return "lock.doc"
        }
    }
}
