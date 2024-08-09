//
//  AppStore.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 2023/7/25.
//

import SwiftUI
import WebKit
import Combine

import ChocofordUI

final class AppPreference: ObservableObject {
    enum SidebarMode: Sendable {
        case all
        case filesOnly
    }
    // Layout
    @Published var sidebarMode: SidebarMode = .all
    
    // Appearence
    enum Appearance: String, RadioGroupCase {
        case light
        case dark
        case auto
        
        var text: String {
            switch self {
                case .light:
                    return "light"
                case .dark:
                    return "dark"
                case .auto:
                    return "auto"
            }
        }
        
        var id: String {
            self.text
        }
        
        var colorScheme: ColorScheme? {
            switch self {
                case .light:
                    return .light
                case .dark:
                    return .dark
                case .auto:
                    return nil
            }
        }
    }
    @AppStorage("appearance") var appearance: Appearance = .auto
    @AppStorage("excalidrawAppearance") var excalidrawAppearance: Appearance = .auto
    
    var appearanceBinding: Binding<ColorScheme?> {
        Binding {
            self.appearance.colorScheme
        } set: { val in
            switch val {
                case .light:
                    self.appearance = .light
                case .dark:
                    self.appearance = .dark
                case .none:
                    self.appearance = .auto
                case .some(_):
                    self.appearance = .light
            }
        }
    }
}

final class FileState: ObservableObject {
    var stateUpdateQueue: DispatchQueue = DispatchQueue(label: "StateUpdateQueue")
    
    var currentGroupPublisherCancellables: [AnyCancellable] = []
    var currentFilePublisherCancellables: [AnyCancellable] = []
    
    @Published var currentGroup: Group? {
        didSet {
            currentGroupPublisherCancellables.forEach {$0.cancel()}
            guard let currentGroup else { return }
            currentGroupPublisherCancellables = [
                currentGroup.publisher(for: \.name).sink { [weak self] _ in
                    self?.objectWillChange.send()
                }
            ]
        }
    }
    @Published var currentFile: File? {
        didSet {
            recoverWatchUpdate.cancel()
            shouldIgnoreUpdate = true
            stateUpdateQueue.asyncAfter(deadline: .now().advanced(by: .milliseconds(1500)), execute: recoverWatchUpdate)
            
            currentFilePublisherCancellables.forEach{$0.cancel()}
            if let currentFile {
                currentFilePublisherCancellables = [
                    currentFile.publisher(for: \.name).sink { [weak self] _ in
                        self?.objectWillChange.send()
                    },
                    currentFile.publisher(for: \.updatedAt).sink { [weak self] _ in
                        self?.objectWillChange.send()
                    }
                ]
            }
        }
    }
    
    
    
    var shouldIgnoreUpdate = false
    /// Indicate the file is being updated after being set as current file.
    var didUpdateFile = false
    var isCreatingFile = false
    
    lazy var recoverWatchUpdate = DispatchWorkItem(flags: .assignCurrentContext) {
        self.shouldIgnoreUpdate = false
    }
    
    func createNewGroup(name: String) throws {
        let group = try PersistenceController.shared.createGroup(name: name)
        currentGroup = group
    }
    func createNewFile(active: Bool = true) throws {
        guard let currentGroup else { throw AppError.stateError(.currentGroupNil) }
        let file = try PersistenceController.shared.createFile(in: currentGroup)
        if active {
            currentFile = file
        }
    }
    
    func updateCurrentFileData(data: Data) {
        guard !shouldIgnoreUpdate || currentFile?.inTrash != true else { return }
        do {
            if let file = currentFile {
                try file.updateElements(with: data, newCheckpoint: !didUpdateFile)
                didUpdateFile = true
            } else if !isCreatingFile {
                
            }
            PersistenceController.shared.save()
        } catch {
            
        }
    }
    
    func importFile(_ url: URL) throws {
        guard url.pathExtension == "excalidraw" else { throw AppError.fileError(.invalidURL) }
        // .uncached fixes the import bug occurs in x86 mac OS
        let data = try Data(contentsOf: url, options: .uncached)
        guard let currentGroup else { throw AppError.stateError(.currentGroupNil) }
        let file = try PersistenceController.shared.createFile(in: currentGroup)
        file.name = url.deletingPathExtension().lastPathComponent
        file.content = data
        PersistenceController.shared.save()
        DispatchQueue.main.async {
            self.currentFile = file
        }
    }
    
    func renameFile(_ file: File, newName: String) {
        file.name = newName
        PersistenceController.shared.save()
    }
    
    func renameGroup(_ group: Group, newName: String) {
        group.name = newName
        PersistenceController.shared.save()
    }
    
    func moveFile(_ file: File, to group: Group) {
        file.group = group
        currentGroup = group
        currentFile = file
        PersistenceController.shared.save()
    }
    
    func duplicateFile(_ file: File) {
        let newFile = PersistenceController.shared.duplicateFile(file: file)
        currentFile = newFile
        PersistenceController.shared.save()
    }
    
    func deleteFile(_ file: File) {
        file.inTrash = true
        if file == currentFile {
            currentFile = nil
        }
        PersistenceController.shared.save()
    }
    
    func recoverFile(_ file: File) {
        guard file.inTrash else { return }
        file.inTrash = false
        
        currentGroup = file.group
        currentFile = file
        PersistenceController.shared.save()
    }

    func deleteFilePermanently(_ file: File) {
        PersistenceController.shared.container.viewContext.delete(file)
        PersistenceController.shared.save()
        if file == currentFile {
            currentFile = nil
        }
    }
    
    func deleteGroup(_ group: Group) throws {
        if group.groupType == .trash {
            let files = try PersistenceController.shared.listTrashedFiles()
            files.forEach { PersistenceController.shared.container.viewContext.delete($0) }
        } else {
            guard let defaultGroup = try PersistenceController.shared.getDefaultGroup() else { throw AppError.fileError(.notFound) }
            let groupFiles: [File] = group.files?.allObjects as? [File] ?? []
            for file in groupFiles {
                file.inTrash = true
                file.deletedAt = .now
                file.group = defaultGroup
            }
            PersistenceController.shared.container.viewContext.delete(group)
        }
        PersistenceController.shared.save()
        
        if group == currentGroup {
            currentGroup = nil
        }
    }
}

final class ExportState: ObservableObject {
    enum Status {
        case notRequested
        case loading
        case finish
    }
    
    var excalidrawWebCoordinator: ExcalidrawView.Coordinator?
    
    @Published var status: Status = .notRequested
    var download: WKDownload?
    var url: URL?
    
    
    enum ExportType {
        case image, file
    }
    func requestExport(type: ExportType) async throws {
        switch type {
            case .image:
                  try await excalidrawWebCoordinator?.exportPNG()
            case .file:
                break
        }
    }
    
    
    func beginExport(url: URL, download: WKDownload) {
        self.status = .loading
        self.url = url
        self.download = download
    }
    
    func finishExport(download: WKDownload) {
        if download == self.download {
            self.status = .finish
        }
    }
}
