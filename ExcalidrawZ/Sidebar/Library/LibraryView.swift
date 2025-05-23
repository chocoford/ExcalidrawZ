//
//  LibraryView.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 2024/9/2.
//

import SwiftUI
import CoreData

import SFSafeSymbols
import ChocofordEssentials
import ChocofordUI
import UniformTypeIdentifiers

struct LibraryView: View {
    @Environment(\.containerHorizontalSizeClass) private var containerHorizontalSizeClass
    @Environment(\.containerVerticalSizeClass) private var containerVerticalSizeClass
    @Environment(\.alertToast) var alertToast
    @EnvironmentObject var appPreference: AppPreference
    @EnvironmentObject var exportState: ExportState
    @EnvironmentObject var layoutState: LayoutState
        
    @FetchRequest(sortDescriptors: [SortDescriptor(\.id)], animation: .smooth)
    var libraries: FetchedResults<Library>
    
    @StateObject private var viewModel = LibraryViewModel()
    
    // each library contains one library item...
    @State private var librariesToImport: [ExcalidrawLibrary] = []
    @State private var image: Image?
    
    @State private var isFileImpoterPresented: Bool = false
    @State private var isImportSheetPresented: Bool = false
    @State private var isRemoveAllConfirmationPresented: Bool = false
    @State private var isRemoveSelectionsConfirmationPresented: Bool = false
    @State private var isFileExporterPresented: Bool = false
    
    @State private var scrollViewSize: CGSize = .zero
    
    @State private var isDropTargeted: Bool = false
    
    @State private var inSelectionMode: Bool = false
    @State private var selectedItems = Set<LibraryItem>()
    
    var body: some View {
        ZStack {
            if #available(macOS 13.0, *), appPreference.inspectorLayout == .sidebar {
                content()
                    .toolbar(content: toolbar)
                    .presentationDetents([.medium])
            } else {
                VStack(spacing: 0) {
                    Divider()
                    content()
                }
            }
        }
        .sheet(isPresented: $isImportSheetPresented) {
            ExcalidrawLibraryImportSheetView(libraries: librariesToImport)
                .frame(minWidth: 700)
        }
        .onDrop(of: [.excalidrawlibFile], isTargeted: $isDropTargeted) { providers in
            librariesToImport.removeAll()
            let canDrop = providers.contains(where: {$0.hasItemConformingToTypeIdentifier(UTType.excalidrawlibFile.identifier)})
            print("canDrop: \(canDrop)")
            guard canDrop else { return false }
            Task {
                do {
                    for provider in providers {
                        let url: URL? = try await withCheckedThrowingContinuation { continuation in
                            provider.loadFileRepresentation(forTypeIdentifier: UTType.excalidrawlibFile.identifier) { url, error in
                                if let error {
                                    continuation.resume(throwing: error)
                                    return
                                }
                                continuation.resume(returning: url)
                            }
                        }
                        guard url != nil else { continue }
                        let data: Data? = try await withCheckedThrowingContinuation { continuation in
                            provider.loadDataRepresentation(forTypeIdentifier: UTType.excalidrawlibFile.identifier) { url, error in
                                if let error {
                                    continuation.resume(throwing: error)
                                    return
                                }
                                continuation.resume(returning: url)
                            }
                        }
                        guard data != nil else { continue }
                        var library = try JSONDecoder().decode(ExcalidrawLibrary.self, from: data!)
                        library.name = url!.deletingPathExtension().lastPathComponent
                        librariesToImport.append(library)
                    }
                    if !librariesToImport.isEmpty {
                        isImportSheetPresented = true
                    }
                } catch {
                    alertToast(error)
                }
            }
            return true
        }
        .fileImporterWithAlert(
            isPresented: $isFileImpoterPresented,
            allowedContentTypes: [.excalidrawlibFile],
            allowsMultipleSelection: true
        ) { urls in
            for url in urls {
                _ = url.startAccessingSecurityScopedResource()
                let data = try Data(contentsOf: url)
                var library = try JSONDecoder().decode(ExcalidrawLibrary.self, from: data)
                library.name = url.deletingPathExtension().lastPathComponent
                self.librariesToImport.append(library)
                url.stopAccessingSecurityScopedResource()
            }
            isImportSheetPresented.toggle()
        }
        .onChange(of: isImportSheetPresented) { newValue in
            if !newValue {
                librariesToImport.removeAll()
            }
        }
        .environmentObject(viewModel)
        .onAppear {
            viewModel.excalidrawWebCoordinator = exportState.excalidrawWebCoordinator
        }
    }
    
    @MainActor @ToolbarContentBuilder
    private func toolbar() -> some ToolbarContent {
#if os(macOS)
        ToolbarItem(placement: .destructiveAction) {
            Color.clear
        }
        
        /// This is the key to make sidebar toggle at the right side.
        /// The `status` is work well in macOS 15.0+. But not well in macOS 14.0
        ToolbarItemGroup(placement: {
            if #available(macOS 15.0, iOS 18.0, *) {
                .status
            } else {
                .cancellationAction
            }
        }()) {
            if layoutState.isInspectorPresented {
                if #available(macOS 15.0, iOS 18.0, *) {} else {
                    Spacer()
                }
                Text(.localizable(.librariesTitle))
                    .foregroundStyle(.secondary)
                    .font(.headline)
                if #available(macOS 15.0, iOS 18.0, *) {} else {
                    Spacer()
                }
            } else {
                Color.clear
                    .frame(width: 1)
            }
        }
        ToolbarItem(placement: .confirmationAction) {
            Button {
                layoutState.isInspectorPresented.toggle()
            } label: {
                Label(.localizable(.librariesTitle), systemSymbol: .sidebarRight)
            }
            .keyboardShortcut("0", modifiers: [.command, .option])
        }
#elseif os(iOS)
        ToolbarItem(placement: .principal) {
            Text(.localizable(.librariesTitle))
                .foregroundStyle(.secondary)
                .font(.headline)
        }
        
        ToolbarItem(placement: .topBarTrailing) {
            if containerHorizontalSizeClass == .regular {
                Button {
                    layoutState.isInspectorPresented.toggle()
                } label: {
                    Label(.localizable(.librariesTitle), systemSymbol: .sidebarRight)
                }
            } else if containerVerticalSizeClass == .compact {
                Button {
                    layoutState.isInspectorPresented.toggle()
                } label: {
                    Label(.localizable(.librariesTitle), systemSymbol: .chevronDown)
                }
            }
        }
#endif
    }
    
    @MainActor @ViewBuilder
    private func content() -> some View {
        if libraries.isEmpty {
            emptyPlaceholder()
        } else {
            VStack(spacing: 0) {
                scrollContent()
                    .readSize($scrollViewSize)
                
                Divider()
                
                bottomBar()
                    .padding(.vertical, 2)
                    .padding(.horizontal, 8)
                    .frame(height: 32)
            }
        }
    }
    
    @MainActor @ViewBuilder
    private func emptyPlaceholder() -> some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemSymbol: .book)
                .resizable()
                .scaledToFit()
                .frame(height: 40)
                .foregroundStyle(.secondary)
            VStack(spacing: 10) {
                Text(.localizable(.librariesNoItemsTitle))
                    .foregroundStyle(.secondary)
                    .font(.title)
                Text(.localizable(.librariesNoItemsDescription))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 10)
            }
            VStack(spacing: 8) {
                importButton()
                    .controlSize(.large)
                Link(destination: URL(string: "https://libraries.excalidraw.com")!) {
                    Text(.localizable(.librariesNoItemsGoToExcalidrawLibraries))
                        .font(.callout)
                }
            }
            
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    @MainActor @ViewBuilder
    private func scrollContent() -> some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                ForEach(libraries, id: \.self) { library in
                    LibrarySectionContent(
                        allLibraries: libraries,
                        library: library,
                        selections: inSelectionMode ? $selectedItems : nil
                    )
                }
                
                Color.clear.frame(height: 100)
            }
            .padding(.horizontal, 10)
        }
    }
    
    @MainActor @ViewBuilder
    private func bottomBar() -> some View {
        HStack {
            Color.clear
                .overlay(alignment: .leading) {
                    if !libraries.isEmpty {
                        Button {
                            inSelectionMode.toggle()
                        } label: {
                            Text(.localizable(inSelectionMode ? .librariesButtonSelectCancel : .librariesButtonSelect))
                        }
                        .buttonStyle(.borderless)
                    }
                }
            
            Color.clear
                .overlay(alignment: .center) {
                    if inSelectionMode {
                        Text(.localizable(.librariesItemsSelected(selectedItems.count)))
                            .foregroundStyle(.secondary)
                    } else {
                        Text(.localizable(.librariesItemsCount(libraries.reduce(0, {$0 + ($1.items?.count ?? 0)}))))
                            .foregroundStyle(.secondary)
                    }
                }
            
            Color.clear
                .overlay(alignment: .trailing) {
                    HStack {
                        if inSelectionMode {
                            Button(role: .destructive) {
                                isRemoveSelectionsConfirmationPresented.toggle()
                            } label: {
                                Label(.localizable(.librariesButtonRemoveSelections), systemSymbol: .trash)
                            }
                            .labelStyle(.iconOnly)
                            .disabled(selectedItems.isEmpty)
                            .buttonStyle(.borderless)
                        }
                        
                        if !inSelectionMode || libraries.count > 1 {
                            if #available(macOS 13.0, *) {
                                bottomBarMenu()
                                    .menuStyle(.button)
                                    .buttonStyle(.borderless)
                            } else {
                                bottomBarMenu()
                                    .menuStyle(.borderlessButton)
                            }
                        }
                    }
                }
        }
        .confirmationDialog(.localizable(.librariesRemoveAllConfirmationTitle), isPresented: $isRemoveAllConfirmationPresented) {
            Button(role: .destructive) {
                removeAllItems()
            } label: {
                Label(.localizable(.librariesRemoveAllConfirmationConfirm), systemSymbol: .trash)
            }
        } message: {
            Text(.localizable(.generalCannotUndoMessage))
        }
        .confirmationDialog(
            .localizable(.librariesRemoveSelectionsConfirmationTitle(selectedItems.count)),
            isPresented: $isRemoveSelectionsConfirmationPresented
        ) {
            Button(role: .destructive) {
                removeSelectedItems()
            } label: {
                Label(.localizable(.librariesRemoveSelectionsConfirmationConfirm), systemSymbol: .trash)
            }
        } message: {
            Text(.localizable(.generalCannotUndoMessage))
        }
        .fileExporter(
            isPresented: $isFileExporterPresented,
            documents: libraries.compactMap{
                (try? JSONEncoder().encode(ExcalidrawLibrary(library: $0)), $0.name)
            }.map{ ExcalidrawlibFile(data: $0.0, filename: $0.1) },
            contentType: .excalidrawlibFile
        ) { result in
            switch result {
                case .success:
                    alertToast(.init(displayMode: .hud, type: .complete(.green), title: String(localizable: .librariesExportLibraryDone)))
                case .failure(let failure):
                    alertToast(failure)
            }
        }
    }
    
    @MainActor @ViewBuilder
    private func bottomBarMenu() -> some View {
        Menu {
            bottomBarMenuItems()
                .labelStyle(.titleAndIcon)
        } label: {
            Label(.localizable(.librariesButtonLibraryOptions), systemSymbol: .ellipsis)
                .labelStyle(.iconOnly)
        }
        .fixedSize()
        .menuIndicator(.hidden)
        .contentShape(Rectangle())
    }
    
    @MainActor @ViewBuilder
    private func bottomBarMenuItems() -> some View {
        if inSelectionMode {
            if libraries.count > 1 {
                Menu {
                    ForEach(libraries.filter({$0.name != nil})) { library in
                        Button {
                            moveSelectionsToLibrary(library)
                        } label: {
                            Text(library.name ?? String(localizable: .generalUntitled))
                        }
                    }
                } label: {
                    Label(.localizable(.generalMoveTo), systemSymbol: .trayAndArrowUp)
                }
            }
        } else {
            importButton()
            
            Button {
                isFileExporterPresented.toggle()
            } label: {
                Label(.localizable(.librariesButtonExportAll), systemSymbol: .squareAndArrowUp)
            }
            
            Divider()
            
            Link(destination: URL(string: "https://libraries.excalidraw.com")!) {
                Label(.localizable(.librariesNoItemsGoToExcalidrawLibraries), systemSymbol: .link)
            }
            
            Divider()
            
            Button(role: .destructive) {
                isRemoveAllConfirmationPresented.toggle()
            } label: {
                Label(.localizable(.librariesButtonRemoveAll), systemSymbol: .trash)
            }
        }
    }
    
    @MainActor @ViewBuilder
    private func importButton() -> some View {
        Button {
            isFileImpoterPresented.toggle()
        } label: {
            Label(.localizable(.librariesButtonImport), systemSymbol: .squareAndArrowDown)
        }
    }
    
    private func moveSelectionsToLibrary(_ library: Library) {
        let alertToast = alertToast
        let context = PersistenceController.shared.container.newBackgroundContext()
        let selectedItems = selectedItems
        let targetLibraryID = library.objectID
        Task.detached {
            context.perform {
                guard let targetLibrary = context.object(with: targetLibraryID) as? Library else { return }
                do {
                    for selectedItem in selectedItems {
                        guard let item = context.object(with: selectedItem.objectID) as? LibraryItem else { continue }
                        
                        if targetLibrary == item.library {
                            // do nothing...
                        } else if targetLibrary.items?.contains(where: { ($0 as? LibraryItem)?.id == item.id }) == true {
                            context.delete(item)
                        } else {
                            item.library = targetLibrary
                        }
                    }
                    try context.save()
                    for library in Array(Set(selectedItems.compactMap{$0.library})) {
                        guard let item = context.object(with: library.objectID) as? Library else { continue }
                        if (item.items?.count ?? 0) <= 0 {
                            context.delete(item)
                        }
                    }
                    try context.save()
                    DispatchQueue.main.async {
                        viewModel.objectWillChange.send()
                    }
                } catch {
                    alertToast(error)
                }
            }
        }
        
        self.inSelectionMode = false
        self.selectedItems.removeAll()
    }
    
    private func removeSelectedItems() {
        let alertToast = alertToast
        let context = PersistenceController.shared.container.newBackgroundContext()
        let selectedItems = selectedItems
        Task.detached {
            context.perform {
                do {
                    for selectedItem in selectedItems {
                        guard let item = context.object(with: selectedItem.objectID) as? LibraryItem else { continue }
                        context.delete(item)
                    }
                    try context.save()
                    for library in Array(Set(selectedItems.compactMap{$0.library})) {
                        guard let item = context.object(with: library.objectID) as? Library else { continue }
                        if (item.items?.count ?? 0) <= 0 {
                            context.delete(item)
                        }
                    }
                    try context.save()
                } catch {
                    alertToast(error)
                }
            }
        }
        self.inSelectionMode = false
        self.selectedItems.removeAll()
    }
    
    private func removeAllItems() {
        let alertToast = alertToast
        let context = PersistenceController.shared.container.viewContext
        Task.detached {
            context.perform {
                do {
                    let libraryItemsfetchRequest: NSFetchRequest<NSFetchRequestResult> = NSFetchRequest(entityName: "LibraryItem")
                    let librariesFetchedRequest: NSFetchRequest<NSFetchRequestResult> = NSFetchRequest(entityName: "Library")
                    let deleteRequest1 = NSBatchDeleteRequest(fetchRequest: libraryItemsfetchRequest)
                    let deleteRequest2 = NSBatchDeleteRequest(fetchRequest: librariesFetchedRequest)
                    try context.executeAndMergeChanges(using: deleteRequest1)
                    try context.executeAndMergeChanges(using: deleteRequest2)
                    try context.save()
                } catch {
                    alertToast(error)
                }
            }
        }
    }
    
}

struct ExcalidrawlibFile: FileDocument {
    enum ExcalidrawlibFileError: Error {
        case initFailed
        case makeFileWrapperFailed
    }
    
    static var readableContentTypes = [UTType.excalidrawlibFile]

    // by default our document is empty
    var data: Data?
    var filename: String?
    
    init(data: Data?, filename: String? = nil) {
        self.data = data
        self.filename = filename
    }
    
    // this initializer loads data that has been saved previously
    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw ExcalidrawlibFileError.initFailed
        }
        self.data = data
    }

    // this will be called when the system wants to write our data to disk
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        guard let data = self.data else { throw ExcalidrawlibFileError.makeFileWrapperFailed }
        let fileWrapper = FileWrapper(regularFileWithContents: data)
        fileWrapper.filename = filename
        return fileWrapper
    }
}

#if DEBUG

struct LibraryPreviewView: View {
    var body: some View {
        if #available(macOS 14.0, iOS 17.0, *) {
            NavigationSplitView {
                
            } detail: {
                
            }
            .inspector(isPresented: .constant(true)) {
                LibraryView()
            }
        } else {
            Color.clear
        }
    }
}

#Preview {
    LibraryPreviewView()
}
#endif
