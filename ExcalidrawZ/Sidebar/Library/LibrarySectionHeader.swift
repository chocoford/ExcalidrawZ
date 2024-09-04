//
//  LibrarySectionHeader.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 2024/9/4.
//

import SwiftUI
import CoreData

import SFSafeSymbols

struct LibrarySectionHeader: View {
    @Environment(\.alertToast) var alertToast

    var allLibraries: FetchedResults<Library>
    var library: Library
    var inSelectionMode: Bool
    
    @State private var isEditLibrarySheetPresented: Bool = false
    @State private var isRemoveLibraryConfimationPresented: Bool = false
    @State private var isFileExporterPresented: Bool = false

    @State private var nameID: TimeInterval = .zero
    
    var body: some View {
        HStack {
            Text(library.name ?? "Untitled")
                .font(.title3.bold())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .id(nameID)
            Spacer()
            if #available(macOS 13.0, *) {
                menuButton()
                    .menuStyle(.button)
                    .buttonStyle(.borderless)
                    .contentShape(Rectangle())
            } else {
                menuButton()
                    .buttonStyle(.borderless)
                    .contentShape(Rectangle())
            }
        }
        .contextMenu {
            menuContent(library: library)
        }
        .confirmationDialog(
            "Are you sure to remove all items of the library",
            isPresented: $isRemoveLibraryConfimationPresented
        ) {
            Button(role: .destructive) {
                removeLibrary()
            } label: {
                Label("Remove", systemSymbol: .trash)
            }
        } message: {
            Text("You can’t undo this action.")
        }
        .sheet(isPresented: $isEditLibrarySheetPresented) {
            RenameSheetView(text: library.name ?? "Untitled") { newName in
                PersistenceController.shared.container.viewContext.perform {
                    library.name = newName
                    try? PersistenceController.shared.container.viewContext.save()
                    nameID = Date().timeIntervalSince1970
                }
            }
        }
        .fileExporter(
            isPresented: $isFileExporterPresented,
            document: ExcalidrawlibFile(
                data: try? JSONEncoder().encode(ExcalidrawLibrary(library: library)),
                filename: library.name
            ),
            contentType: .excalidrawlibFile,
            defaultFilename: library.name
        ) { result in
            switch result {
                case .success:
                    alertToast(.init(displayMode: .hud, type: .complete(.green), title: "Export Library done"))
                case .failure(let failure):
                    alertToast(failure)
            }
        }
    }
    
    @MainActor @ViewBuilder
    private func menuButton() -> some View {
        if !inSelectionMode {
            Menu {
                menuContent(library: library)
            } label: {
                Label("Options", systemSymbol: .ellipsis)
                    .labelStyle(.iconOnly)
            }
            .fixedSize()
            .menuIndicator(.hidden)
        }
    }
    
    @MainActor @ViewBuilder
    private func menuContent(library: Library) -> some View {
        SwiftUI.Group {
            Button {
                isEditLibrarySheetPresented.toggle()
            } label: {
                Label("Rename", systemSymbol: .squareAndPencil)
            }
            
            if allLibraries.count > 1 {
                Menu {
                    ForEach(allLibraries.filter{$0 != library && $0.name != nil}) { library in
                        Button {
                            mergeWithLibrary(library)
                        } label: {
                            Text(library.name ?? "Unknown")
                        }
                    }
                } label: {
                    Label(.localizable(.sidebarGroupRowContextMenuMerge), systemSymbol: .rectangleStackBadgePlus)
                }
            }
            Divider()
            
            Button {
                isFileExporterPresented.toggle()
            } label: {
                Label("Export", systemSymbol: .squareAndArrowUp)
            }
            
            Divider()
            
            Button {
                isRemoveLibraryConfimationPresented = true
            } label: {
                Label("Remove all", systemSymbol: .trash)
            }
        }
        .labelStyle(.titleAndIcon)
    }
    
    private func mergeWithLibrary(_ targetLibrary: Library) {
        let bgContext = PersistenceController.shared.container.newBackgroundContext()
        let targetLibraryID = targetLibrary.objectID
        let sourceLibraryID = self.library.objectID
        let alertToast = alertToast
        Task.detached {
            do {
                try await bgContext.perform {
                    guard let sourceLibrary = bgContext.object(with: sourceLibraryID) as? Library,
                          let targetLibrary = bgContext.object(with: targetLibraryID) as? Library else {
                        return
                    }
                    for item in sourceLibrary.items?.allObjects as? [LibraryItem] ?? [] {
                        if targetLibrary.items?.contains(where: {
                            ($0 as? LibraryItem)?.id == item.id
                        }) == true {
                            bgContext.delete(item)
                        } else {
                            item.library = targetLibrary
                        }
                    }
                    bgContext.delete(sourceLibrary)
                    try bgContext.save()
                }
            } catch {
                alertToast(error)
            }
        }
    }
    
    private func removeLibrary() {
        let alertToast = alertToast
        let id = library.objectID
        let context = PersistenceController.shared.container.newBackgroundContext()
        Task.detached {
            do {
                try await context.perform {
                    guard let library = context.object(with: id) as? Library else { return }
                    for item in library.items?.allObjects as? [LibraryItem] ?? [] {
                        context.delete(item)
                    }
                    context.delete(library)
                    try context.save()
                }
            } catch {
                alertToast(error)
            }
        }
    }
}

