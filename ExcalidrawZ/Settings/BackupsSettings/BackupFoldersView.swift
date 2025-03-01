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
                .disclosureGroupStyle(BackupFoldersDisclosureGroupStyle())
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

private struct DisclosureGroupDepthKey: EnvironmentKey {
    static let defaultValue: Int = 0
}

// 2. Extend the environment with our property
private extension EnvironmentValues {
    var diclosureGroupDepth: Int {
        get { self[DisclosureGroupDepthKey.self] }
        set { self[DisclosureGroupDepthKey.self] = newValue }
    }
}

@available(macOS 13.0, *)
struct BackupFoldersDisclosureGroupStyle: DisclosureGroupStyle {
    @Environment(\.diclosureGroupDepth) private var depth
    
    func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 0) {
                Color.clear
                    .frame(width: CGFloat(depth * 8), height: 1)
                
                Image(systemSymbol: .chevronRight)
                    .font(.footnote)
                    .rotationEffect(.degrees(configuration.isExpanded ? 90 : 0))

                configuration.label
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .padding(.leading, 6)
                
                Spacer()
            }
            .padding(.vertical, 3)
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation {
                    configuration.isExpanded.toggle()
                }
            }
            
            if configuration.isExpanded {
                configuration.content
                    .disclosureGroupStyle(self)
                    .environment(\.diclosureGroupDepth, depth + 1)
            }
        }
    }
}
