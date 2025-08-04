//
//  Content+Searchable.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 3/25/25.
//

import SwiftUI
import CoreData

import ChocofordUI
import SFSafeSymbols

struct ExcalidrawSearchEnvrionmentKey: EnvironmentKey {
    static let defaultValue: SearchExcalidrawAction = SearchExcalidrawAction(isSearchPresented: .constant(false))
}

extension EnvironmentValues {
    var searchExcalidrawAction: SearchExcalidrawAction {
        get { self[ExcalidrawSearchEnvrionmentKey.self] }
        set { self[ExcalidrawSearchEnvrionmentKey.self] = newValue }
    }
}

struct SearchExcalidrawAction {
    @Binding var isSearchPresented: Bool
    
    func callAsFunction() {
        isSearchPresented.toggle()
    }
}


struct SearchableModifier: ViewModifier {
    @State private var isSearchSheetPresented = false
    
    func body(content: Content) -> some View {
        content
            .background {
                Button {
                    isSearchSheetPresented.toggle()
                } label: { }
                    .opacity(0.01)
                    .keyboardShortcut("f", modifiers: .command)
                
                if #available(macOS 14.0, *) { } else {
                    Button {
                        isSearchSheetPresented = false
                    } label: { }
                        .opacity(0.01)
                        .keyboardShortcut(.escape)
                }
            }
            .sheet(isPresented: $isSearchSheetPresented) {
                SerachContent()
                    .swiftyAlert()
#if os(macOS)
                    .frame(width: 500, height: 400)
#endif
            }
            .environment(\.searchExcalidrawAction, SearchExcalidrawAction(isSearchPresented: $isSearchSheetPresented))
    }
}

struct SerachContent: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.alertToast) private var alertToast
    
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var fileState: FileState
    
    var withDismissButton: Bool
    
    init(
        withDismissButton: Bool = true
    ) {
        self.withDismissButton = withDismissButton
    }
    
    @State private var searchText = ""
    
    @State private var searchFiles: [File] = []
    @State private var searchFilesPath: [String] = []
    @State private var searchCollaborationFiles: [CollaborationFile] = []
    @State private var searchLocalFiles: [URL] = []
    
    @State private var isSearching = false
    
    @State private var selectionIndex: Int?
#if os(iOS)
    let tapSelectCount = 1
#elseif os(macOS)
    let tapSelectCount = 2
#endif
    
    var body: some View {
        VStack(spacing: 0) {
            TextField("", text: $searchText, prompt: Text(.localizable(.searchFieldPropmtText)))
                .textFieldStyle(SearchTextFieldStyle())
                .submitLabel(.go)
                .onSubmit {
                    guard let selectionIndex else { return }
                    onSelect(selectionIndex)
                }
                .overlay(alignment: .trailing) {
                    if withDismissButton {
                        Button {
                            dismiss()
                        } label: {
                            Label(.localizable(.generalButtonCancel), systemSymbol: .xmarkCircleFill)
                                .labelStyle(.iconOnly)
                                .foregroundStyle(.secondary)
                                .padding()
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.borderless)
                        .keyboardShortcut(.escape)
                        .padding(.trailing, 20)
                    }
                }

            Divider()

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0, pinnedViews: .sectionHeaders) {
                        collaborationFilesSection()
                        
                        filesSection()
                        
                        localFilesSection()
                    }
                    .padding()
                }
                .onChange(of: selectionIndex) { newValue in
                    if let newValue {
                        withAnimation {
                            if newValue < searchCollaborationFiles.count {
                                proxy.scrollTo(searchCollaborationFiles[newValue])
                            } else if newValue < searchCollaborationFiles.count + searchFiles.count {
                                proxy.scrollTo(searchFiles[newValue - searchCollaborationFiles.count])
                            } else if newValue < searchCollaborationFiles.count + searchFiles.count + searchLocalFiles.count {
                                proxy.scrollTo(searchLocalFiles[newValue - searchCollaborationFiles.count - searchFiles.count])
                            }
                        }
                    }
                }
            }
        }
        .onChange(of: searchText, initial: true, throttle: 0.5, latest: true) { newValue in
            guard !isSearching else { return }
            fetchFiles()
        }
#if canImport(AppKit)
        .onAppear {
            NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { nsevent in
                let maxIndex = searchFiles.count + searchCollaborationFiles.count + searchLocalFiles.count - 1
                if nsevent.keyCode == 125 { // arrow down
                    selectionIndex = min(maxIndex, (selectionIndex ?? -1) + 1)
                } else if nsevent.keyCode == 126 { // arrow up
                    if selectionIndex == 0 {
                        selectionIndex = nil
                    } else if let selectionIndex {
                        self.selectionIndex = max(selectionIndex - 1, 0)
                    }
                }
                return nsevent
            }
        }
#endif
        .onDisappear {
            selectionIndex = nil
            isSearching = false
        }
    }
    
    @MainActor @ViewBuilder
    private func collaborationFilesSection() -> some View {
        if !searchCollaborationFiles.isEmpty {
            searchResultSection(.localizable(.searchResultsSectionCollaborationFilesTitle)) {
                ForEach(Array(searchCollaborationFiles.enumerated()), id: \.element) { i, room in
                    SwiftUI.Group {
#if canImport(AppKit)
                        SearchItemRow(
                            image: NSWorkspace.shared.icon(for: .excalidrawFile),
                            title: room.name ?? String(localizable: .generalUntitled),
                            subtitle: room.updatedAt?.formatted() ?? "",
                            isSelected: selectionIndex == i
                        )
#elseif canImport(UIKit)
                        SearchItemRow(
                            image: UIImage.icon(for: .excalidrawFile),
                            title: room.name ?? String(localizable: .generalUntitled),
                            subtitle: room.updatedAt?.formatted() ?? "",
                            isSelected: selectionIndex == i
                        )
#endif
                    }
                    .onTapGesture(count: tapSelectCount) {
                        dismiss()
                        if let limit = store.collaborationRoomLimits,
                           fileState.collaboratingFiles.count >= limit,
                           !fileState.collaboratingFiles.contains(room) {
                            store.togglePaywall(reason: .roomLimit)
                        } else {
                            fileState.isInCollaborationSpace = true
                            fileState.currentCollaborationFile = .room(room)
                        }
                    }
                }
            }
        }
    }
    
    @MainActor @ViewBuilder
    private func filesSection() -> some View {
        if !searchFiles.isEmpty {
            searchResultSection(.localizable(.searchResultsSectionFilesTitle)) {
                ForEach(Array(searchFiles.enumerated()), id: \.element) { i, file in
                    SwiftUI.Group {
#if canImport(AppKit)
                        SearchItemRow(
                            image: NSWorkspace.shared.icon(for: .excalidrawFile),
                            title: file.name ?? String(localizable: .generalUntitled),
                            subtitle: searchFilesPath[i],
                            isSelected: selectionIndex == i + searchCollaborationFiles.count
                        )
#elseif canImport(UIKit)
                        SearchItemRow(
                            image: UIImage.icon(for: .excalidrawFile),
                            title: file.name ?? String(localizable: .generalUntitled),
                            subtitle: searchFilesPath[i],
                            isSelected: selectionIndex == i + searchCollaborationFiles.count
                        )
#endif
                    }
                    .onTapGesture(count: tapSelectCount) {
                        if let group = file.group {
                            fileState.currentGroup = group
                            fileState.currentFile = file
                            fileState.expandToGroup(group.objectID)
                            dismiss()
                        }
                    }
                }
            }
        }
    }
    
    @MainActor @ViewBuilder
    private func localFilesSection() -> some View {
        if !searchLocalFiles.isEmpty {
            searchResultSection(.localizable(.searchResultsSectionLocalFilesTitle)) {
                ForEach(Array(searchLocalFiles.enumerated()), id: \.element) { i, file in
                    SwiftUI.Group {
#if canImport(AppKit)
                        SearchItemRow(
                            image: NSWorkspace.shared.icon(forFile: file.filePath),
                            title: file.deletingPathExtension().lastPathComponent,
                            subtitle: file.filePath,
                            isSelected: selectionIndex == i + searchCollaborationFiles.count + searchFiles.count
                        )
#elseif canImport(UIKit)
                        SearchItemRow(
                            image: UIImage.icon(forFileURL: file),
                            title: file.deletingPathExtension().lastPathComponent,
                            subtitle: file.filePath,
                            isSelected: selectionIndex == i + searchCollaborationFiles.count + searchFiles.count
                        )
#endif
                    }
                    .onTapGesture(count: tapSelectCount) {
                        Task {
                            do {
                                try await viewContext.perform {
                                    let fetchRequest = NSFetchRequest<LocalFolder>(entityName: "LocalFolder")
                                    fetchRequest.predicate = NSPredicate(format: "filePath = %@", file.deletingLastPathComponent().filePath)
                                    if let folder = try viewContext.fetch(fetchRequest).first {
                                        fileState.currentLocalFolder = folder
                                        fileState.currentLocalFile = file
                                        fileState.expandToGroup(folder.objectID)
                                        dismiss()
                                    }
                                }
                            } catch {
                                alertToast(error)
                            }
                        }
                    }
                }
            }
        }
    }
    
    
    @MainActor @ViewBuilder
    private func searchResultSection<Content: View>(
        _ header: LocalizedStringKey,
        @ViewBuilder content: () -> Content
    ) -> some View {
        Section {
            content()
        } header: {
            HStack {
                Text(header)
                Spacer()
            }
            .font(.headline)
            .padding(4)
            .background(.background)
#if canImport(AppKit)
            .visualEffect(material: .sheet)
#endif
        }
    }
    
    private func getFileGroupPath(file: File) -> String {
        if file.inTrash {
            return "In Trash..."
        }
        var tree: [Group] = []
        var group: Group? = file.group
        if let group {
            tree.insert(group, at: 0)
        }
        while let parent = group?.parent {
            tree.insert(parent, at: 0)
            group = parent
        }
        return tree.map{ $0.name ?? String(localizable: .generalUntitled) }.joined(separator: " > ")
    }
    
    private func fetchFiles() {
        Task {
            isSearching = true
            do {
                try await viewContext.perform {
                    let fileFetchRequest = NSFetchRequest<File>(entityName: "File")
                    if !searchText.isEmpty {
                        fileFetchRequest.predicate = NSPredicate(format: "name contains %@", searchText)
                    }
                    let searchFiles = try viewContext.fetch(fileFetchRequest)
                    
                    var searchLocalFiles: [URL] = []
                    let localFolderFetchRequest = NSFetchRequest<LocalFolder>(entityName: "LocalFolder")
                    let localFolders = try viewContext.fetch(localFolderFetchRequest)
                    for folder in localFolders {
                        let localFiles = try folder.withSecurityScopedURL { scopedURL in
                            let contents = try FileManager.default.contentsOfDirectory(at: scopedURL, includingPropertiesForKeys: [])
                            return contents
                                .filter({$0.pathExtension == "excalidraw"})
                                .filter({
                                    searchText.isEmpty ||
                                    $0.deletingPathExtension().lastPathComponent.contains(searchText)
                                })
                        }
                        searchLocalFiles.append(contentsOf: localFiles)
                    }
                    
                    let collaborationFilesFetchRequest = NSFetchRequest<CollaborationFile>(entityName: "CollaborationFile")
                    if !searchText.isEmpty {
                        collaborationFilesFetchRequest.predicate = NSPredicate(format: "name contains %@", searchText)
                    }
                    let searchCollaborationFiles = try viewContext.fetch(collaborationFilesFetchRequest)
                    
                    self.searchFiles = searchFiles
                    self.searchLocalFiles = searchLocalFiles
                    self.searchCollaborationFiles = searchCollaborationFiles
                    
                    self.searchFilesPath = searchFiles.map {
                        getFileGroupPath(file: $0)
                    }
                }
            } catch {
                alertToast(error)
            }
            isSearching = false
        }
    }
    
    private func onSelect(_ index: Int) {
        if index < searchCollaborationFiles.count {
            dismiss()
            let file = searchCollaborationFiles[index]
            if let limit = store.collaborationRoomLimits,
               fileState.collaboratingFiles.count >= limit,
               !fileState.collaboratingFiles.contains(file) {
                store.togglePaywall(reason: .roomLimit)
            } else {
                fileState.isInCollaborationSpace = true
                fileState.currentCollaborationFile = .room(file)
            }
        } else if index < searchCollaborationFiles.count + searchFiles.count {
            let file = searchFiles[index - searchCollaborationFiles.count]
            if let group = file.group {
                fileState.currentGroup = group
                fileState.currentFile = file
                fileState.expandToGroup(group.objectID)
                dismiss()
            }
        } else if index < searchCollaborationFiles.count + searchFiles.count + searchLocalFiles.count {
            Task {
                let file = searchLocalFiles[index - searchCollaborationFiles.count - searchFiles.count]
                do {
                    try await viewContext.perform {
                        let fetchRequest = NSFetchRequest<LocalFolder>(entityName: "LocalFolder")
                        fetchRequest.predicate = NSPredicate(format: "filePath = %@", file.deletingLastPathComponent().filePath)
                        if let folder = try viewContext.fetch(fetchRequest).first {
                            fileState.currentLocalFolder = folder
                            fileState.currentLocalFile = file
                            fileState.expandToGroup(folder.objectID)
                            dismiss()
                        }
                    }
                } catch {
                    alertToast(error)
                }
            }
        }
    }
}

fileprivate struct SearchTextFieldStyle: TextFieldStyle {
    @FocusState private var isFocused: Bool
    
    public func _body(configuration: TextField<Self._Label>) -> some View {
        HStack {
            Image(systemSymbol: .magnifyingglass)
            
            configuration
                .focused($isFocused)
                .textFieldStyle(.plain)
        }
    }
}

fileprivate struct SearchItemRow: View {
    
#if canImport(AppKit)
    typealias PlatformImage = NSImage
#elseif canImport(UIKit)
    typealias PlatformImage = UIImage
#endif
    
    var image: PlatformImage?
    var title: String
    var subtitle: String
    var isSelected: Bool
    
    init(
        image: PlatformImage?,
        title: String,
        subtitle: String,
        isSelected: Bool
    ) {
        self.image = image
        self.title = title
        self.subtitle = subtitle
        self.isSelected = isSelected
    }
    
    @State private var icon: Image?
    @State private var isLoading = true
    
    @State private var isHovered = false
    
    var body: some View {
        HStack(spacing: 10) {
            if #available(macOS 15.0, iOS 18.0, *) {
                icon ?? Image(systemSymbol: .document)
            } else {
                icon ?? Image(systemSymbol: .doc)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.headline)
                Text(subtitle).font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .background {
            if isHovered {
                RoundedRectangle(cornerRadius: 8)
                    .fill(.regularMaterial)
            }
            if isSelected {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.accentColor, lineWidth: 2)
            }
        }
        .onHover { isHovered in
            withAnimation {
                self.isHovered = isHovered
            }
        }
        .opacity(icon == nil ? 0 : 1)
        .onAppear {
            guard let image else { return }
            Task.detached { [image] in
                let image = Image(platformImage: image)
                await MainActor.run {
                    self.icon = image
                    isLoading = false
                }
            }
        }
    }
}

#Preview {
    SerachContent()
}
