//
//  AppStore.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 2023/7/25.
//

import SwiftUI

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
    @Published var currentGroup: Group?
    @Published var currentFile: File? {
        didSet {
            recoverWatchUpdate.cancel()
            shouldIgnoreUpdate = true
            stateUpdateQueue.asyncAfter(deadline: .now().advanced(by: .milliseconds(1500)), execute: recoverWatchUpdate)
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
        guard let currentGroup else { return }
        let file = try PersistenceController.shared.createFile(in: currentGroup)
        currentFile = file
    }
    
    func updateCurrentFileData(data: Data) {
        guard !shouldIgnoreUpdate || currentFile?.inTrash != true else { return }
        do {
            if let file = currentFile {
                try file.updateElements(with: data, newCheckpoint: !didUpdateFile)
                didUpdateFile = true
            } else if !isCreatingFile {
                
            }
        } catch {
            
        }
    }
    
    func renameFile(_ file: File, newName: String) {
        file.name = newName
    }
    
    func moveFile(_ file: File, to group: Group) {
        file.group = group
        currentGroup = group
        currentFile = file
    }
    
    func duplicateFile(_ file: File) {
        let newFile = PersistenceController.shared.duplicateFile(file: file)
        currentFile = newFile
    }
    
    func deleteFile(_ file: File) {
        file.inTrash = true
        if file == currentFile {
            currentFile = nil
        }
    }
    
    func recoverFile(_ file: File) {
        guard file.inTrash else { return }
        file.inTrash = false
        
        currentGroup = file.group
        currentFile = file
    }

    func deleteFilePermanently(_ file: File) {
        PersistenceController.shared.container.viewContext.delete(file)
        PersistenceController.shared.save()
        if file == currentFile {
            currentFile = nil
        }
    }
}
