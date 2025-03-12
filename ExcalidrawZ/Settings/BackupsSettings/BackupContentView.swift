//
//  BackupContentView.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 3/7/25.
//

import SwiftUI

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
                LazyVStack(spacing: 0) {
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
        .watchImmediately(of: backup) { newValue in
            loadSelectedBackup()
        }
    }
    
    private func loadSelectedBackup() {
        // selectedBackupDirs.removeAll()
        var accSize: Int = 0
        do {
            let groups: [URL] = try FileManager.default.contentsOfDirectory(
                at: backup,
                includingPropertiesForKeys: [.nameKey, .isDirectoryKey]
            ).filter({ (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true })
            
            self.backupRootFolders = groups
            
            guard let enumerator = FileManager.default.enumerator(
                at: backup,
                includingPropertiesForKeys: [.nameKey, .isDirectoryKey, .fileSizeKey]
            ) else {
                return
            }
            
            for case let url as URL in enumerator {
                guard url.pathExtension == "excalidraw" else { continue }
                accSize += ((try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize) ?? 0
            }
            self.selectedBackupSize = accSize

            
//            for group in groups {
//                let files: [URL] = try FileManager.default.contentsOfDirectory(
//                    at: group,
//                    includingPropertiesForKeys: [.nameKey, .fileSizeKey]
//                )
//                selectedBackupDirs.updateValue(files, forKey: group.lastPathComponent)
//                
//                accSize += files.reduce(0) { partialResult, url in
//                    partialResult + ((try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
//                }
//            }
//            
//            self.selectedBackupSize = accSize
        } catch {
            alertToast(error)
        }
    }

}
