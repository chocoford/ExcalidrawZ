//
//  BackupsSettingsView.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 2024/11/15.
//

import SwiftUI

import ChocofordUI

#if os(macOS)
struct BackupsSettingsView: View {
    @Environment(\.alertToast) var alertToast
    
    @State private var backups: [URL] = []
    
    @State private var selectedBackup: URL?
    @State private var selectedBackupSize: Int = 0

    @State private var selectedBackupDirs: [String : [URL]] = [:]
    
    @State private var selectedFile: URL?
    
    @State private var backupToBeDeleted: URL?
    
    var body: some View {
        HStack {
            ScrollView {
                LazyVStack {
                    ForEach(backups, id: \.self) { item in
                        Button {
                            selectedBackup = item
                            selectedFile = nil
                        } label: {
                            Text(item.lastPathComponent)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        .buttonStyle(.listCell(selected: selectedBackup == item))
                        .contextMenu {
                            Button(role: .destructive) {
                                backupToBeDeleted = item
                            } label: {
                                Label("Delete", systemSymbol: .trash)
                                    .labelStyle(.titleAndIcon)
                            }
                        }
                    }
                }
                .padding(10)
                .frame(minHeight: 400, alignment: .top)
                .background {
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture {
                            selectedBackup = nil
                        }
                }
            }
            .frame(width: 120)
            .visualEffect(material: .sidebar)

            backupContent()
                .frame(maxWidth: .infinity)
                .watchImmediately(of: selectedBackup) { _ in
                    loadSelectedBackup()
                }
        }
        .confirmationDialog(
            "Are you sure to delete this backup?",
            isPresented: Binding { backupToBeDeleted != nil } set: { if !$0 { backupToBeDeleted = nil } }
        ) {
            Button(role: .destructive) {
                deleteBackup()
            } label: {
                Text("Confirm")
            }
        }
        .onAppear {
            loadBackups()
        }
    }
    
    @MainActor @ViewBuilder
    private func backupContent() -> some View {
        if let backup = selectedBackup {
            HStack(spacing: 0) {
                ScrollView {
                    VStack {
                        ForEach(Array(selectedBackupDirs), id: \.key) { (groupName, files) in
                            DisclosureGroup(groupName) {
                                ForEach(files, id: \.self) { file in
                                    Button {
                                        selectedFile = file
                                    } label: {
                                        Text(file.deletingPathExtension().lastPathComponent)
                                            .lineLimit(1)
                                            .truncationMode(.middle)
                                    }
                                    .buttonStyle(.listCell(selected: selectedFile == file))
                                }
                            }
                        }
                    }
                    .padding(10)
                    .background {
                        Color.clear
                            .contentShape(Rectangle())
                            .onTapGesture {
                                selectedFile = nil
                            }
                    }
                }
                .frame(width: 200)
                
                Divider()
                
                ZStack {
                    if let selectedFile, let excalidrawFile = try? ExcalidrawFile(contentsOf: selectedFile) {
                        ExcalidrawRenderer(file: excalidrawFile)
                    } else {
                        backupHomeView(backup)
                    }
                }
                .frame(maxWidth: .infinity)
            }
        } else {
            placeholderView()
        }

    }
    
    @MainActor @ViewBuilder
    private func placeholderView() -> some View {
        VStack {
            Text("Backups").font(.largeTitle)
//            Text("Your data is regularly backed up.").foregroundStyle(.secondary)
            VStack(alignment: .leading) {
                Text("To ensure the safety of your data, backups are performed daily and retained for one week. Beyond one week, backups are kept at weekly intervals, and beyond one month, they are retained at monthly intervals, and so on.")
                Divider()
                Text("Now, you can select a specific backup from the sidebar on the left and view its details.")
            }
            .padding()
            .background {
                let roundedRectangle = RoundedRectangle(cornerRadius: 8)
                ZStack {
                    roundedRectangle.fill(.regularMaterial)
                    if #available(macOS 13.0, iOS 17.0, *) {
                        roundedRectangle.stroke(.separator)
                    } else {
                        roundedRectangle.stroke(.secondary)
                    }
                }
            }
        }
        .frame(maxWidth: 400)
    }
    
    @MainActor @ViewBuilder
    private func backupHomeView(_ backup: URL) -> some View {
        let title = "Backup at \((try? backup.resourceValues(forKeys: [.creationDateKey]).creationDate?.formatted()) ?? "Unknwon")"
        VStack {
            Text(title).font(.title)
            
            Text("Total size: \(selectedBackupSize.formatted(.byteCount(style: .file)))")
            
            HStack {
                Button {
                    do {
                        let panel = NSSavePanel()
                        panel.nameFieldStringValue = title
                        if panel.runModal() == .OK, let targetURL = panel.url {
                            try FileManager.default.copyItem(at: backup, to: targetURL)
                        }
                    } catch {
                        alertToast(error)
                    }
                } label: {
                    Label("Export", systemSymbol: .squareAndArrowUp)
                }
                
                Button(role: .destructive) {
                    backupToBeDeleted = backup
                } label: {
                    Label("Delete", systemSymbol: .trash)
                }
            }
        }
    }
    
    private func loadBackups() {
        do {
            let backupsDir = try getBackupsDir()
            
            let backupDirs: [URL] = try FileManager.default.contentsOfDirectory(
                at: backupsDir,
                includingPropertiesForKeys: [.nameKey, .isDirectoryKey]
            ).filter({ (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true })
                        
            self.backups = backupDirs
            
        } catch {
            
        }
    }
    
    private func loadSelectedBackup() {
        selectedBackupDirs.removeAll()
        guard let selectedBackup else { return }
        var accSize: Int = 0
        do {
            let groups: [URL] = try FileManager.default.contentsOfDirectory(
                at: selectedBackup,
                includingPropertiesForKeys: [.nameKey, .isDirectoryKey]
            ).filter({ (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true })
            
            for group in groups {
                let files: [URL] = try FileManager.default.contentsOfDirectory(
                    at: group,
                    includingPropertiesForKeys: [.nameKey, .fileSizeKey]
                )//.filter({ (try? $0.resourceValues(forKeys: [.nameKey]))?.name?.hasSuffix("excalidraw") == true })
                selectedBackupDirs.updateValue(files, forKey: group.lastPathComponent)
                
                accSize += files.reduce(0) { partialResult, url in
                    partialResult + ((try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
                }
            }
            
            self.selectedBackupSize = accSize
        } catch {
            alertToast(error)
        }
    }
    
    private func deleteBackup() {
        guard let item = backupToBeDeleted, let index = backups.firstIndex(of: item) else {
            return
        }
        do {
            try FileManager.default.removeItem(at: item)
            backups.remove(at: index)
            selectedBackup = nil
            selectedBackupSize = 0
            selectedBackupDirs = [:]
            selectedFile = nil
        } catch {
            alertToast(error)
        }
    }
}
#elseif os(iOS)
struct BackupsSettingsView: View {
    var body: some View {
        Text("Backup is only available on macOS.")
    }
}
#endif
#Preview {
    BackupsSettingsView()
}
