//
//  BackupFoldersView.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 2/28/25.
//

import SwiftUI

import ChocofordUI

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
    
    @State private var content: [URL] = []
    
    
    var body: some View {
        if #available(macOS 13.0, *) {
            contentView()
                .disclosureGroupStyle(.leadingChevron)
        } else {
            contentView()
        }
    }
    
    @MainActor @ViewBuilder
    private func contentView() -> some View {
        DisclosureGroup {
            ForEach(content, id: \.self) { url in
                if (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true {
                    BackupFoldersView(selection: $selection, folder: url, depth: depth + 1)
                } else if let name = (try? url.resourceValues(forKeys: [.nameKey]))?.name,
                          name.hasSuffix(".excalidraw") {
                    Button {
                        selection = url
                    } label: {
                        HStack(spacing: 4) {
                            Label(url.deletingPathExtension().lastPathComponent, systemSymbol: .doc)
                                .symbolVariant(.fill)
                                .padding(.leading, CGFloat(8 * depth) + 14)
                        }
                        .lineLimit(1)
                        .truncationMode(.tail)
                    }
                    .buttonStyle(ListButtonStyle(selected: selection == url))
                }
            }
        } label: {
            HStack(spacing: 4) {
                let folderName = folder.lastPathComponent
                Label(folderName, systemSymbol: depth == 0 ? (folderName == "Cloud" ? .cloud : (folderName == "Local" ? .externaldrive : .folder)) : .folder)
                    .symbolVariant(.fill)
            }
        }
        .onAppear {
            do {
                self.content = try FileManager.default.contentsOfDirectory(
                    at: folder,
                    includingPropertiesForKeys: [.nameKey, .isDirectoryKey],
                    options: .skipsHiddenFiles
                )
            } catch {
                alertToast(error)
            }
        }
    }
}

