//
//  ContainerToolbar.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 2024/11/18.
//

import SwiftUI

import ChocofordUI

struct ExcalidrawContainerToolbarContentModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.containerHorizontalSizeClass) private var containerHorizontalSizeClass
    @Environment(\.alertToast) private var alertToast
    
    @EnvironmentObject var appPreference: AppPreference
    @EnvironmentObject var layoutState: LayoutState
    @EnvironmentObject var fileState: FileState
    @EnvironmentObject var toolState: ToolState
    
    @State private var isCollaboratorPopoverPresented = false
    
    func body(content: Content) -> some View {
        ZStack {
            if containerHorizontalSizeClass == .compact {
                if #available(iOS 18.0, *) {
                    content
#if os(iOS)
                        .navigationBarBackButtonHidden()
                        .toolbarBackgroundVisibility(.hidden, for: .automatic)
                        // .toolbarBackgroundVisibility(.hidden, for: .bottomBar)
                        .toolbarBackgroundVisibility(.hidden, for: .navigationBar)
#endif
                } else {
                    content
#if os(iOS)
                        .navigationBarBackButtonHidden()
#endif
                }
            } else {
                if #available(iOS 18.0, *) {
                    content
#if os(iOS)
                        .toolbarVisibility(.hidden, for: .bottomBar)
#endif
                } else {
                    content
#if os(iOS)
                        .toolbar(.hidden, for: .bottomBar)
#endif
                }
            }
        }
        .toolbar(content: toolbarContent)
#if os(iOS)
//        .modifier(
//            HideToolbarModifier(
//                isPresented: toolState.isBottomBarPresented,
//                placement: .bottomBar
//            )
//        )
        .animation(.default, value: toolState.isBottomBarPresented)
        .toolbarBackground(containerHorizontalSizeClass == .regular ? .automatic : .visible, for: .bottomBar)
        .toolbarBackground(
            fileState.currentActiveGroup == .collaboration && fileState.currentActiveFile == nil ? .hidden : .visible,
            for: .navigationBar
        )
        .navigationBarTitleDisplayMode(.inline) // <- fix principal toolbar
#endif
    }
    
    @ToolbarContentBuilder
    private func toolbarContent() -> some ToolbarContent {
#if os(iOS)
        toolbarContent_iOS()
#else
        toolbarContent_macOS()
#endif
    }
    
#if os(iOS)
    @ToolbarContentBuilder
    private func toolbarContent_iOS() -> some ToolbarContent {
        ToolbarItemGroup(
            placement: containerHorizontalSizeClass == .regular ? .principal : .bottomBar
        ) {
            ExcalidrawToolbar()
        }
        
        toolbarContent_macOS()
    }
#endif

    @ToolbarContentBuilder
    private func toolbarContent_macOS() -> some ToolbarContent {
        ToolbarItemGroup(placement: .navigation) {
            if #available(macOS 13.0, iOS 16.0, *),
               appPreference.sidebarLayout == .sidebar {

            } else if #available(macOS 13.0, iOS 16.0, *),
               appPreference.sidebarLayout == .sidebar {
                
            } else if containerHorizontalSizeClass != .compact {
                Button {
                    layoutState.isSidebarPresented.toggle()
                } label: {
                    Label(.localizable(.sidebarToggleName), systemSymbol: .sidebarLeft)
                }
            }
            
            if fileState.currentActiveGroup != nil {
                HStack {
                    NavigationBackButton()
                    if containerHorizontalSizeClass == .compact {
                        title()
                        titleBarActionsMenu()
                    }
                }
            }
            
            if #available(macOS 13.0, iOS 16.0, *) { } else {
                NewFileButton()
            }
        }
#if os(macOS)
        ToolbarItemGroup(placement: .status) {
            if #available(macOS 26.0, iOS 26.0, *) {
                ExcalidrawToolbar()
            } else if #available(macOS 13.0, iOS 16.0, *) {
                ExcalidrawToolbar()
                .padding(.vertical, 2)
            } else {
                ExcalidrawToolbar()
            }
        }
#endif
        
//        ToolbarItemGroup(placement: .confirmationAction) {
        ToolbarItemGroup(placement: .primaryAction) {
            if fileState.currentActiveFile != nil {
#if os(iOS)
                applePencilToggle()
#endif
                FileHistoryButton()
                
                ShareToolbarButton()
            }
#if os(iOS)
            if #available(iOS 26.0, *) {
                if containerHorizontalSizeClass == .compact,
                   fileState.currentActiveFile == nil {
                    
                } else if !layoutState.isInspectorPresented {
                    inspectorButton()
                }
            } else if appPreference.inspectorLayout == .sidebar {
                if !layoutState.isInspectorPresented {
                    inspectorButton()
                }
            }
#endif
            if #available(macOS 13.0, iOS 16.0, *),
                appPreference.inspectorLayout == .sidebar {

            } else {
                Button {
                    layoutState.isInspectorPresented.toggle()
                } label: {
                    Label(.localizable(.librariesTitle), systemSymbol: .sidebarRight)
                }
            }
        }
    }
    
    @MainActor @ViewBuilder
    private func inspectorButton() -> some View {
        Button {
            layoutState.isInspectorPresented.toggle()
        } label: {
            Label(.localizable(.librariesTitle), systemSymbol: .sidebarRight)
        }
    }
    
    @MainActor @ViewBuilder
    private func undoButton() -> some View {
        if let excalidrawCore = fileState.excalidrawWebCoordinator {
            if excalidrawCore.canUndo, excalidrawCore.canRedo {
                Menu {
                    AsyncButton { @MainActor in
                        try await excalidrawCore.performUndo()
                    } label: {
                        Label(.localizable(.generalButtonUndo), systemSymbol: .arrowUturnBackward)
                    }
                    AsyncButton { @MainActor in
                        try await excalidrawCore.performRedo()
                    } label: {
                        Label(.localizable(.generalButtonRedo), systemSymbol: .arrowUturnForward)
                    }
                } label: {
                    Label(.localizable(.generalButtonUndo), systemSymbol: .arrowUturnBackwardCircle)
                } primaryAction: {
                    Task {
                        do {
                            try await excalidrawCore.performUndo()
                        } catch {
                            alertToast(error)
                        }
                    }
                }
            } else if excalidrawCore.canRedo {
                Menu {
                    AsyncButton { @MainActor in
                        try await excalidrawCore.performUndo()
                    } label: {
                        Label(.localizable(.generalButtonUndo), systemSymbol: .arrowUturnBackward)
                    }
                    .disabled(true)
                    AsyncButton { @MainActor in
                        try await excalidrawCore.performRedo()
                    } label: {
                        Label(.localizable(.generalButtonRedo), systemSymbol: .arrowUturnForward)
                    }
                } label: {
                    Label(.localizable(.generalButtonUndo), systemSymbol: .arrowUturnBackwardCircle)
                        .foregroundStyle(.gray)
                }
            } else if excalidrawCore.canUndo {
                AsyncButton { @MainActor in
                    try await excalidrawCore.performUndo()
                } label: {
                    Label(.localizable(.generalButtonUndo), systemSymbol: .arrowUturnBackwardCircle)
                }
            } else {
                Button { } label: {
                    Label(.localizable(.generalButtonUndo), systemSymbol: .arrowUturnBackwardCircle)
                }
                .disabled(true)
            }
        }
    }
    
    @MainActor @ViewBuilder
    private func title() -> some View {
        if let activeFile = fileState.currentActiveFile {
            ZStack {
                switch activeFile {
                    case .file(let file):
                        VStack(alignment: .leading) {
                            Text(file.name ?? String(localizable: .generalUntitled))
                                .font(.headline)
                            Text(file.updatedAt?.formatted() ?? "Not modified")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    case .localFile(let fileURL):
                        let filename = fileURL.deletingPathExtension().lastPathComponent
                        let updatedAt = (try? FileManager.default.attributesOfItem(atPath: fileURL.filePath))?[.modificationDate] as? Date
                        VStack(alignment: .leading) {
                            Text(filename)
                                .font(.headline)
                            Text(updatedAt?.formatted() ?? "Not modified")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    case .temporaryFile(let fileURL):
                        let filename = fileURL.deletingPathExtension().lastPathComponent
                        let updatedAt = (try? FileManager.default.attributesOfItem(atPath: fileURL.filePath))?[.modificationDate] as? Date
                        VStack(alignment: .leading) {
                            Text(filename)
                                .font(.headline)
                            Text(updatedAt?.formatted() ?? "Not modified")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    case .collaborationFile(let collaborationFile):
                        HStack(spacing: 10) {
                            VStack(alignment: .leading) {
                                Text(collaborationFile.name ?? String(localizable: .generalUntitled))
                                    .font(.headline)
                                Text(collaborationFile.updatedAt?.formatted() ?? "Not modified")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                            
                            if containerHorizontalSizeClass != .compact {
                                CollaborationMembersPopoverButton()
                            }
                        }
                }
            }
            .frame(width: 120, alignment: .leading)
        }
    }
    
    @MainActor @ViewBuilder
    private func titleBarActionsMenu() -> some View {
        if let file = fileState.currentActiveFile {
            ZStack {
                switch file {
                    case .file(let file):
                        FileMenu(files: [file]) {
                            fileMenuLabel()
                        }
                    case .localFile(let url):
                        LocalFileMenu(file: url) {
                            fileMenuLabel()
                        }
                    case .temporaryFile(let url):
                        Menu {
                            TemporaryFileMenuItems(file: url)
                                .labelStyle(.titleAndIcon)
                        } label: {
                            fileMenuLabel()
                        }
                    case .collaborationFile(let collaborationFile):
                        CollaborationFileMenu(file: collaborationFile) {
                            fileMenuLabel()
                        }
                }
            }
            .labelsHidden()
            .controlSize(.small)
            .padding(.trailing, 8)
            .fixedSize()
        }
    }
    
    @MainActor @ViewBuilder
    private func fileMenuLabel() -> some View {
#if os(iOS)
        Image(systemSymbol: .ellipsis)
            .font(.footnote)
#endif
    }
    
    @MainActor @ViewBuilder
    private func applePencilToggle() -> some View {
        if containerHorizontalSizeClass == .regular {
            Button {
                Task {
                    toolState.inPenMode.toggle()
                    do {
                        try await toolState.excalidrawWebCoordinator?.togglePenMode(enabled: toolState.inPenMode)
                        try await toolState.toggleTool(.freedraw)
                    } catch {
                        toolState.inPenMode.toggle()
                    }
                }
            } label: {
                Label("Apple Pencil", systemSymbol: .pencilTipCropCircle)
                    .symbolVariant(toolState.inPenMode ? .fill : .none)
            }
        }
    }
}

#if os(iOS)
struct HideToolbarModifier: ViewModifier {
    @EnvironmentObject private var fileState: FileState
    
    var isPresented: Bool
    var placement: ToolbarPlacement
    
    init(isPresented: Bool, placement: ToolbarPlacement) {
        self.isPresented = isPresented
        self.placement = placement
    }
    
    func body(content: Content) -> some View {
        if #available(macOS 15.0, iOS 18.0, *) {
            content
                .toolbarVisibility(isPresented && fileState.currentActiveFile != nil ? .automatic : .hidden, for: placement)
        } else {
            content
                .toolbar(isPresented && fileState.currentActiveFile != nil ? .automatic : .hidden, for: placement)
        }
    }
}
#endif


struct NavigationBackButton: View {
    @EnvironmentObject var fileState: FileState

    var body: some View {
        Button {
            if fileState.currentActiveFile != nil {
                fileState.currentActiveFile = nil
            } else {
                switch fileState.currentActiveGroup {
                    case .group(let group):
                        fileState.currentActiveGroup = group.parent != nil ? .group(group.parent!) : nil
                    case .localFolder(let localFolder):
                        fileState.currentActiveGroup = localFolder.parent != nil
                        ? .localFolder(localFolder.parent!)
                        : nil
                    default:
                        fileState.currentActiveGroup = nil
                }
            }
        } label: {
            Label(.localizable(.navigationButtonBack), systemSymbol: .chevronBackward)
        }
    }
}

struct CollaborationMembersPopoverButton: View {
    @EnvironmentObject private var fileState: FileState
    
    @State private var isCollaboratorPopoverPresented = false
    
    init() {}
    
    var body: some View {
        HStack(spacing: 0) {
            Button {
                isCollaboratorPopoverPresented.toggle()
            } label: {
                Label("Collborators", systemSymbol: .person2)
            }
            .disabled(fileState.currentCollaborators.isEmpty)
            .popover(isPresented: $isCollaboratorPopoverPresented, arrowEdge: .bottom) {
                if #available(macOS 13.0, *) {
                    CollaboratorsList()
                        .scrollContentBackground(.hidden)
                } else {
                    CollaboratorsList()
                }
                
            }
            
            Text("\(fileState.currentCollaborators.count)")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}
