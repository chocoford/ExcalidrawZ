//
//  BackupContentView.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 3/7/25.
//

import SwiftUI

private struct BackupSummary: Sendable {
    let rootFolders: [URL]
    let totalSize: Int
}

struct BackupContentView: View {
    @Environment(\.alertToast) var alertToast

    var backup: URL
    @Binding var selectedFile: URL?
    @Binding private var selectedBackupSize: Int
    
    init(
        backup: URL,
        selectedFile: Binding<URL?>,
        selectedBackupSize: Binding<Int>
    ) {
        self.backup = backup
        self._selectedFile = selectedFile
        self._selectedBackupSize = selectedBackupSize
    }
    
    @State private var backupRootFolders: [URL] = []
    // @State private var selectedBackupDirs: [String : [URL]] = [:]
    
    var body: some View {
        HStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(backupRootFolders, id: \.self) { folder in
                        BackupFoldersView(selection: $selectedFile, folder: folder)
                    }
                }
                .padding(.horizontal)
                .frame(minHeight: 400, alignment: .top)
                .background {
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture {
                            selectedFile = nil
                        }
                }
            }
        }
        .task(id: backup) {
            await loadSelectedBackup()
        }
    }
    
    @MainActor
    private func loadSelectedBackup() async {
        do {
            let backupURL = backup
            let summary = try await Task.detached(priority: .utility) {
                try Self.loadBackupSummary(from: backupURL)
            }.value
            guard !Task.isCancelled else {
                return
            }
            self.backupRootFolders = summary.rootFolders
            self.selectedBackupSize = summary.totalSize
        } catch {
            alertToast(error)
        }
    }

    private nonisolated static func loadBackupSummary(
        from backup: URL
    ) throws -> BackupSummary {
        let groups = try FileManager.default.contentsOfDirectory(
            at: backup,
            includingPropertiesForKeys: [.nameKey, .isDirectoryKey],
            options: .skipsHiddenFiles
        )
        .filter { url in
            (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
        }

        var totalSize = 0
        guard let enumerator = FileManager.default.enumerator(
            at: backup,
            includingPropertiesForKeys: [.nameKey, .isDirectoryKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else {
            return BackupSummary(rootFolders: groups, totalSize: totalSize)
        }

        for case let url as URL in enumerator where url.pathExtension == "excalidraw" {
            totalSize += ((try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize) ?? 0
        }

        return BackupSummary(rootFolders: groups, totalSize: totalSize)
    }

}
