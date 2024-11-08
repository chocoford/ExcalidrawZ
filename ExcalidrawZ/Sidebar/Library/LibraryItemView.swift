//
//  LibraryItemView.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 2024/9/2.
//

import SwiftUI
import UniformTypeIdentifiers

import ChocofordUI

struct LibraryItemView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.alertToast) var alertToast
    
    @EnvironmentObject var libraryViewModel: LibraryViewModel
    
    var item: LibraryItem
    var size: CGFloat = 80
    var inSelectionMode: Bool
    var libraries: FetchedResults<Library>
    
    init(
        item: LibraryItem,
        size: CGFloat = 80,
        inSelectionMode: Bool,
        libraries: FetchedResults<Library>
    ) {
        self.item = item
        self.size = size
        self.inSelectionMode = inSelectionMode
        self.libraries = libraries
    }
    
    @State private var isDeleteConfirmPresented = false

    var body: some View {
        LibraryItemContentView(item: item)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .font(.footnote)
        .lineLimit(1)
        .truncationMode(.middle)
        .onDrag {
            let itemProvider = NSItemProvider()
            itemProvider.registerDataRepresentation(
                forTypeIdentifier: UTType.excalidrawlibJSON.identifier,
                visibility: .ownProcess
            ) { completion in
                viewContext.perform {
                    do {
                        let item = item.excalidrawLibrary
                        let data = try item.jsonStringified().data(using: .utf8)
                        completion(data, nil)
                    } catch {
                        alertToast(error)
                        completion(nil, error)
                    }
                }
                return Progress(totalUnitCount: 100)
            }
            return itemProvider
        }
        .contextMenu { contextMenu().labelStyle(.titleAndIcon) }
        .confirmationDialog(.localizable(.librariesRemoveItemConfirmationTitle), isPresented: $isDeleteConfirmPresented) {
            AsyncButton(role: .destructive) {
                try await deleteLibraryItem()
            } label: {
                Label(.localizable(.librariesRemoveItemConfirmationConfirm), systemSymbol: .trash)
            }
        } message: {
            Text(.localizable(.generalCannotUndoMessage))
        }
    }
    
    @MainActor @ViewBuilder
    private func contextMenu() -> some View {
        if !inSelectionMode {
            Button {
                Task {
                    do {
                        try await libraryViewModel.excalidrawWebCoordinator?.loadLibraryItem(item: item.excalidrawLibrary)
                    } catch {
                        alertToast(error)
                    }
                }
            } label: {
                Label(.localizable(.librariesButtonItemAddToCanvas), systemSymbol: .plusSquare)
            }

            if libraries.count > 1 {
                Menu {
                    ForEach(libraries.filter({$0.name != nil && $0 != self.item.library})) { library in
                        Button {
                            moveToLibrary(library)
                        } label: {
                            Text(library.name ?? "Untitled")
                        }
                    }
                } label: {
                    Label(.localizable(.generalMoveTo), systemSymbol: .trayAndArrowUp)
                }
            }
            
            Divider()
            Button(role: .destructive) {
                isDeleteConfirmPresented.toggle()
            } label: {
                Label(.localizable(.librariesItemRemove), systemSymbol: .trash)
                    .foregroundStyle(.red)
            }
        }
    }
    
    private func moveToLibrary(_ library: Library)  {
        let context = PersistenceController.shared.container.newBackgroundContext()
        let alertToast = alertToast
        let itemID = item.objectID
        let libraryID = library.objectID
        Task.detached {
            do {
                try await context.perform {
                    guard let item = context.object(with: itemID) as? LibraryItem,
                          let targetLibrary = context.object(with: libraryID) as? Library else { return }
                    
                    if targetLibrary.items?.contains(where: { ($0 as? LibraryItem)?.id == item.id }) == true {
                        context.delete(item)
                    } else {
                        item.library = targetLibrary
                    }
                    try context.save()
                    DispatchQueue.main.async {
                        libraryViewModel.objectWillChange.send()
                    }
                }
            } catch {
                alertToast(error)
            }
        }
    }
    
    private func deleteLibraryItem() async throws {
        let context = PersistenceController.shared.container.newBackgroundContext()
        let itemID = self.item.objectID
        try await context.perform {
            guard let item = context.object(with: itemID) as? LibraryItem else {
                return
            }
            context.delete(item)
            try context.save()
        }
    }
}
#if os(macOS)
let excalidrawLibItemsCache: NSCache = NSCache<NSString, NSImage>()
#else
let excalidrawLibItemsCache: NSCache = NSCache<NSString, UIImage>()
#endif

struct LibraryItemContentView: View {
    @Environment(\.colorScheme) var colorScheme
    @EnvironmentObject var appPreference: AppPreference

    @EnvironmentObject var exportState: ExportState
    
    var item: ExcalidrawLibrary
    var size: CGFloat = 80
    
    init(item: ExcalidrawLibrary, size: CGFloat = 80) {
        self.item = item
        self.size = size
    }
    
    init(item: LibraryItem, size: CGFloat = 80) {
        self.item = item.excalidrawLibrary
        self.size = size
    }
    
    @State private var image: Image?

    
    var body: some View {
        ZStack {
            if appPreference.excalidrawAppearance == .light || (appPreference.excalidrawAppearance == .auto && colorScheme == .light) {
                content()
            } else if appPreference.excalidrawAppearance == .dark || (appPreference.excalidrawAppearance == .auto && colorScheme == .dark) {
                content()
                    .colorInvert()
                    .hueRotation(Angle(degrees: 180))
            }
        }
        .onAppear {
            guard let webCoordinator = exportState.excalidrawWebCoordinator else { return }
            Task.detached {
                do {
                    let image: Image
                    if let platformImage = excalidrawLibItemsCache.object(forKey: NSString(string: item.libraryItems[0].id)) {
                        image = Image(platformImage: platformImage)
                    } else {
                        let nsImage = try await webCoordinator.exportElementsToPNG(
                            elements: item.libraryItems[0].elements
                        )
                        excalidrawLibItemsCache.setObject(nsImage, forKey: NSString(string: item.libraryItems[0].id))
                        image = Image(platformImage: nsImage)
                    }
                    await MainActor.run {
                        self.image = image
                    }
                } catch {
                    dump(error)
                }
            }
        }
    }
    
    @MainActor @ViewBuilder
    private func content() -> some View {
        Center {
            VStack {
                if let image {
                    image
                        .resizable()
                        .scaledToFit()
                } else {
                    Color.clear
                }
            }
        }
        .frame(height: size)
        .aspectRatio(1, contentMode: .fit)
        .background(.white)
    }
    
}
