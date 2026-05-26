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

    @Binding var librariesToImport: [ExcalidrawLibrary]
    
    init(
        librariesToImport: Binding<[ExcalidrawLibrary]>
    ) {
        self._librariesToImport = librariesToImport
    }
    
    @StateObject private var viewModel = LibraryViewModel()
    
    // each library contains one library item...
    @State private var image: Image?
    
    @State private var isFileImpoterPresented: Bool = false
    @State private var isRemoveAllConfirmationPresented: Bool = false
    @State private var isRemoveSelectionsConfirmationPresented: Bool = false
    @State private var isFileExporterPresented: Bool = false
    
    @State private var scrollViewSize: CGSize = .zero
    
    
    @State private var inSelectionMode: Bool = false
    @State private var selectedItems = Set<LibraryItem>()

    @State private var searchQuery: String = ""

    @State private var isLibraryBrowserPresented: Bool = false
    /// Set inside the browser sheet when the user opts to import from file —
    /// consumed in `onDismiss` to trigger the file importer once the sheet has
    /// fully animated away (presenting two sheets back-to-back races otherwise).
    @State private var pendingFileImportAfterBrowser: Bool = false
    
    var body: some View {
        ZStack {
            if #available(macOS 13.0, *), appPreference.inspectorLayout == .sidebar {
                content()
#if os(macOS)
                    .toolbar(content: toolbar)
#endif
                    .presentationDetents([.medium])
            } else {
                VStack(spacing: 0) {
                    Divider()
                    content()
                }
            }
        }
        .modifier(ExcalidrawLibraryDropHandler())
        .fileImporterWithAlert(
            isPresented: $isFileImpoterPresented,
            allowedContentTypes: [.excalidrawlibFile],
            allowsMultipleSelection: true
        ) { urls in
            var libraries: [ExcalidrawLibrary] = []
            for url in urls {
                _ = url.startAccessingSecurityScopedResource()
                let data = try Data(contentsOf: url)
                var library = try JSONDecoder().decode(ExcalidrawLibrary.self, from: data)
                library.name = url.deletingPathExtension().lastPathComponent
                libraries.append(library)
                url.stopAccessingSecurityScopedResource()
            }
            self.librariesToImport = libraries
        }
        .environmentObject(viewModel)
        .onAppear {
            viewModel.excalidrawWebCoordinator = exportState.excalidrawWebCoordinator
        }
        .sheet(isPresented: $isLibraryBrowserPresented, onDismiss: {
            if pendingFileImportAfterBrowser {
                pendingFileImportAfterBrowser = false
                isFileImpoterPresented = true
            }
        }) {
            LibraryBrowserSheet(onRequestManualImport: {
                pendingFileImportAfterBrowser = true
            })
        }
        // These were attached to `bottomBar()` originally, but the toolbar buttons
        // now share the same flags — and on macOS 26+ the bottom bar isn't even in
        // the view tree, so the modifiers must live at body level to be reachable.
        .confirmationDialog(
            String(localizable: .librariesRemoveAllConfirmationTitle),
            isPresented: $isRemoveAllConfirmationPresented
        ) {
            Button(role: .destructive) {
                removeAllItems()
            } label: {
                Label(.localizable(.librariesRemoveAllConfirmationConfirm), systemSymbol: .trash)
            }
        } message: {
            Text(.localizable(.generalCannotUndoMessage))
        }
        .confirmationDialog(
            {
                if #available(macOS 13.0, iOS 16.0, *) {
                    String(localizable: .librariesRemoveSelectionsConfirmationTitle(selectedItems.count))
                } else {
                    String(localizable: .generalButtonDelete)
                }
            }(),
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

#if os(macOS)
    @available(macOS 13.0, *)
    @MainActor @ToolbarContentBuilder
    private func toolbar() -> some ToolbarContent {
        if layoutState.isInspectorPresented {
            if #available(macOS 26.0, *) {
                ToolbarItemGroup(placement: .destructiveAction) {
                    if !libraries.isEmpty {
                        Button {
                            inSelectionMode.toggle()
                            if !inSelectionMode { selectedItems.removeAll() }
                        } label: {
                            Label(
                                .localizable(inSelectionMode ? .librariesButtonSelectCancel : .librariesButtonSelect),
                                systemSymbol: inSelectionMode ? .xmark : .checklist
                            )
                        }
                    }
                    
                }
                
                // This work...
                ToolbarItemGroup(placement: .principal) {
                    Spacer()
                }
                
                // Not working...
                ToolbarSpacer(.fixed)
            }
            
            InspectorHeaderToolbar(
                title: String(localizable: .librariesTitle),
                isInspectorPresented: layoutState.isInspectorPresented
            )
            
            if #available(macOS 26.0, *) {
                ToolbarItemGroup(placement: .automatic) {
                    if inSelectionMode {
                        Button(role: .destructive) {
                            isRemoveSelectionsConfirmationPresented.toggle()
                        } label: {
                            Label(.localizable(.librariesButtonRemoveSelections), systemSymbol: .trash)
                        }
                        .disabled(selectedItems.isEmpty)
                    }
                    
                    Menu {
                        bottomBarMenuItems()
                            .labelStyle(.titleAndIcon)
                    } label: {
                        Label(.localizable(.librariesButtonLibraryOptions), systemSymbol: .ellipsis)
                    }
                    .menuIndicator(.hidden)
                }
            }
        }
    }
#endif

    @MainActor @ViewBuilder
    private func content() -> some View {
        if libraries.isEmpty {
            emptyPlaceholder()
        } else {
            if containerHorizontalSizeClass == .compact {
#if os(iOS)
                compactContent()
#endif
            } else {
                VStack(spacing: 0) {
                    searchField
                        .padding(.horizontal, 10)
                        .padding(.top, 8)
                        .padding(.bottom, 4)
                    
                    scrollContent()
                        .readSize($scrollViewSize)
                    
                    if #available(macOS 26.0, *) { } else {
                        Divider()
                        
                        bottomBar()
#if os(iOS)
                            .padding(.vertical, 8)
                            .padding(.horizontal, 16)
                            .frame(height: 56, alignment: .top)
#else
                            .padding(.vertical, 2)
                            .padding(.horizontal, 8)
                            .frame(height: 32)
#endif
                    }
                }
            }
        }
    }

    @MainActor @ViewBuilder
    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemSymbol: .magnifyingglass)
                .foregroundStyle(.secondary)
            TextField(
                "",
                text: $searchQuery,
                prompt: Text(localizable: .libraryItemsSearchPrompt)
            )
                .textFieldStyle(.plain)
            if !searchQuery.isEmpty {
                Button {
                    searchQuery = ""
                } label: {
                    Image(systemSymbol: .xmarkCircleFill)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background {
            Capsule()
                .fill(.regularMaterial)
        }
    }
    
#if os(iOS)
    @MainActor @ViewBuilder
    private func compactContent() -> some View {
        NavigationStack {
            VStack(spacing: 0) {
                searchField
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 4)

                scrollContent()
                    .readSize($scrollViewSize)
            }
            .navigationTitle(.localizable(.librariesTitle))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigation) {
                    ToolbarDismissButton()
                }

                ToolbarItem(placement: .automatic) {
                    if inSelectionMode {
                        ToolbarDoneButton {
                            inSelectionMode.toggle()
                        }
                    } else {
                        bottomBarMenu()
                    }
                }
            }
        }
    }
#endif
    
    
    
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
                    .modernButtonStyle(size: .large, shape: .modern)
                Link(destination: URL(string: "https://libraries.excalidraw.com")!) {
                    Text(.localizable(.librariesNoItemsGoToExcalidrawLibraries))
                        .font(.callout)
                }
                .hoverCursor(.link)
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
                        selections: inSelectionMode ? $selectedItems : nil,
                        searchQuery: searchQuery
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
#if os(iOS)
                        .hoverEffect()
#endif
                    }
                }
            
            Color.clear
                .overlay(alignment: .center) {
                    if inSelectionMode {
                        if #available(macOS 13.0, iOS 16.0, *) {
                            Text(.localizable(.librariesItemsSelected(selectedItems.count)))
                                .foregroundStyle(.secondary)
                        } else {
                            Text(selectedItems.count.formatted())
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        if #available(macOS 13.0, iOS 16.0, *) {
                            Text(.localizable(.librariesItemsCount(libraries.reduce(0, {$0 + ($1.items?.count ?? 0)}))))
                                .foregroundStyle(.secondary)
                        } else {
                            Text(libraries.reduce(0, {$0 + ($1.items?.count ?? 0)}).formatted())
                                .foregroundStyle(.secondary)
                        }
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
#if os(iOS)
                            .hoverEffect()
#endif
                        }
                        
                        if !inSelectionMode || libraries.count > 1 {
                            if #available(macOS 13.0, *) {
                                bottomBarMenu()
                                    .menuStyle(.button)
                                    .buttonStyle(.borderless)
#if os(iOS)
                                    .hoverEffect()
#endif
                            } else {
                                bottomBarMenu()
                                    .menuStyle(.borderlessButton)
                            }
                        }
                    }
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
            
            Button {
                isLibraryBrowserPresented = true
            } label: {
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
        // Now opens the in-app library browser; users can drill into a manual
        // file import from the sheet's header if they have a local .excalidrawlib.
        Button {
            isLibraryBrowserPresented = true
        } label: {
            Label(.localizable(.librariesButtonImport), systemSymbol: .squareAndArrowDown)
        }
    }
    
    private func moveSelectionsToLibrary(_ library: Library) {
        let alertToast = alertToast
        let context = PersistenceController.shared.container.newBackgroundContext()
        let selectedItems = selectedItems
        let targetLibraryID = library.objectID
        let selectedItemIDs = selectedItems.map{$0.objectID}
        let libraryIDs = Array(Set(selectedItems.compactMap{$0.library})).map { $0.objectID }
        Task.detached {
            context.perform {
                guard let targetLibrary = context.object(with: targetLibraryID) as? Library else { return }
                do {
                    for selectedItemID in selectedItemIDs {
                        guard let item = context.object(with: selectedItemID) as? LibraryItem else { continue }
                        
                        if targetLibrary == item.library {
                            // do nothing...
                        } else if targetLibrary.items?.contains(where: { ($0 as? LibraryItem)?.id == item.id }) == true {
                            context.delete(item)
                        } else {
                            item.library = targetLibrary
                        }
                    }
                    try context.save()
                    for libraryID in libraryIDs {
                        guard let item = context.object(with: libraryID) as? Library else { continue }
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
        let selectedItemIDs = selectedItems.map { $0.objectID }
        let libraryIDs = Array(Set(selectedItems.compactMap{$0.library})).map { $0.objectID }
        Task.detached {
            context.perform {
                do {
                    for id in selectedItemIDs {
                        guard let item = context.object(with: id) as? LibraryItem else { continue }
                        context.delete(item)
                    }
                    try context.save()
                    for libraryID in libraryIDs {
                        guard let item = context.object(with: libraryID) as? Library else { continue }
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
                LibraryView(librariesToImport: .constant([]))
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
