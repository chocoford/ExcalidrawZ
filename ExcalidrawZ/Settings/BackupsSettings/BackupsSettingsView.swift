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
    
    enum Route: Hashable {
        case dateList
        case folderList
    }
    
    @State private var route: Route = .dateList
    
    var body: some View {
        HStack(spacing: 0) {
            ZStack {
                switch route {
                    case .dateList:
                        backupsDateList()
                    case .folderList:
                        VStack(spacing: 0) {
                            HStack {
                                Button {
                                    route = .dateList
                                    self.selectedBackup = nil
                                    self.selectedFile = nil
                                } label: {
                                    Label(.localizable(.navigationButtonBack), systemSymbol: .chevronLeft)
                                }
                                .buttonStyle(.borderless)
                                Spacer()
                            }
                            .padding(6)
                            .transition(.opacity)
                            
                            if let selectedBackup {
                                BackupContentView(
                                    backup: selectedBackup,
                                    selectedFile: $selectedFile,
                                    selectedBackupSize: $selectedBackupSize
                                )
                                .transition(.opacity.combined(with: .offset(x: 50)).animation(.smooth(duration: 0.2)))
                            }
                        }
                        .animation(.default, value: selectedBackup)
                }
            }
            .clipped()
            .animation(.default, value: route)
            .frame(width: 240)
            .visualEffect(material: .sidebar)

            Divider()
            
            ZStack {
                if let selectedFile, let excalidrawFile = try? ExcalidrawFile(contentsOf: selectedFile) {
                    ExcalidrawRenderer(file: excalidrawFile)
                } else if let selectedBackup {
                    backupHomeView(selectedBackup)
                } else {
                    placeholderView()
                }
            }
            .frame(maxWidth: .infinity)
        }
        .confirmationDialog(
            .localizable(.backupsDeleteConfirmationTitle),
            isPresented: Binding { backupToBeDeleted != nil } set: { if !$0 { backupToBeDeleted = nil } }
        ) {
            Button(role: .destructive) {
                deleteBackup()
            } label: {
                Text(.localizable(.generalButtonConfirm))
            }
        }
        .onAppear {
            loadBackups()
        }
    }
    
    @MainActor @ViewBuilder
    private func backupsDateList() -> some View {
        ScrollView {
            LazyVStack(spacing: 4) {
                ForEach(backups, id: \.self) { item in
                    Button {
                        route = .folderList
                        selectedBackup = item
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
                            Label(.localizable(.generalButtonDelete), systemSymbol: .trash)
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
    }
    
    
    @MainActor @ViewBuilder
    private func placeholderView() -> some View {
        VStack {
            Text(.localizable(.settingsBackupsName)).font(.largeTitle)
            VStack(alignment: .leading) {
                Text(.localizable(.settingsBackupsDescription))
                Divider()
                Text(.localizable(.settingsBackupsDescriptionSecondary))
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
        let title = String(
            localizable: .backupName(
                (try? backup.resourceValues(forKeys: [.creationDateKey]).creationDate?.formatted()) ?? String(localizable: .generalUnknown)
            )
        )
    
        VStack {
            Text(title).font(.title)
            
            Text(String(localizable: .generalTotalSizeLabel) + selectedBackupSize.formatted(.byteCount(style: .file)))
            
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
                    Label(.localizable(.backupButtonExport), systemSymbol: .squareAndArrowUp)
                }
                
                Button(role: .destructive) {
                    backupToBeDeleted = backup
                } label: {
                    Label(.localizable(.backupButtonDelete), systemSymbol: .trash)
                }
            }
        }
    }
    
    private func loadBackups() {
        do {
            let backupsDir = try getBackupsDir()
            
            let backupDirs: [URL] = try FileManager.default.contentsOfDirectory(
                at: backupsDir,
                includingPropertiesForKeys: [.nameKey, .isDirectoryKey, .creationDateKey]
            )
                .filter({ (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true })
                .sorted(by: {
                    ((try? $0.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? .distantPast) > ((try? $1.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? .distantPast)
                })
                        
            self.backups = backupDirs
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
        Text(.localizable(.settingsBackupUnavailableDescription))
    }
}
#endif
#Preview {
    BackupsSettingsView()
}
