//
//  ContainerToolbar.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 2024/11/18.
//

import SwiftUI

import ChocofordUI

struct ExcalidrawContainerToolbarContentModifier: ViewModifier {
//    @Environment(\.dismiss) var dismiss
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.containerHorizontalSizeClass) private var containerHorizontalSizeClass
    @Environment(\.alertToast) private var alertToast
    
    @EnvironmentObject var appPreference: AppPreference
    @EnvironmentObject var layoutState: LayoutState
    @EnvironmentObject var fileState: FileState
    @EnvironmentObject var toolState: ToolState

    @State private var sharedFile: ExcalidrawFile?
    
    func body(content: Content) -> some View {
        ZStack {
            if containerHorizontalSizeClass == .compact {
                content
#if os(iOS)
                    .navigationBarBackButtonHidden()
#endif
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
        .modifier(HideToolbarModifier(isPresented: toolState.isBottomBarPresented, placement: .bottomBar))
        .animation(.default, value: toolState.isBottomBarPresented)
        .toolbarBackground(containerHorizontalSizeClass == .regular ? .automatic : .visible, for: .bottomBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .navigationBarTitleDisplayMode(.inline) // <- fix principal toolbar
#endif
        .modifier(ShareFileModifier(sharedFile: $sharedFile))
    }
    
    @ToolbarContentBuilder
    private func toolbarContent() -> some ToolbarContent {
#if os(iOS)
        toolbarContent_iOS()
#else
        toolbarContent_macOS()
#endif
    }
    
    @ToolbarContentBuilder
    private func toolbarContent_iOS() -> some ToolbarContent {
        toolbarContent_macOS()
    }

    @ToolbarContentBuilder
    private func toolbarContent_macOS() -> some ToolbarContent {
#if os(macOS)
        ToolbarItemGroup(placement: .status) {
            if #available(macOS 13.0, iOS 16.0, *) {
                ExcalidrawToolbar()
                .padding(.vertical, 2)
            } else {
                ExcalidrawToolbar()
                    .offset(y: layoutState.isExcalidrawToolbarDense ? 0 : 6)
            }
        }
#elseif os(iOS)
        ToolbarItemGroup(
            placement: containerHorizontalSizeClass == .regular ? .principal : .bottomBar
        ) {
            ExcalidrawToolbar()
        }
#endif
        
        ToolbarItemGroup(placement: .navigation) {
            if #available(macOS 13.0, iOS 16.0, *), appPreference.sidebarLayout == .sidebar {
                
            } else if containerHorizontalSizeClass != .compact {
                Button {
                    layoutState.isSidebarPresented.toggle()
                } label: {
                    Label(.localizable(.sidebarToggleName), systemSymbol: .sidebarLeft)
                }
            }
            
#if os(macOS)
            title()
#endif

            if #available(macOS 13.0, iOS 16.0, *) { } else {
                NewFileButton()
            }
        }
        
#if os(iOS)
        ToolbarItemGroup(placement: .topBarLeading) {
            if containerHorizontalSizeClass == .compact {
                Button {
                    fileState.currentFile = nil
                    fileState.currentLocalFile = nil
                    fileState.currentTemporaryFile = nil
                } label: {
                    Label(.localizable(.navigationButtonBack), systemSymbol: .chevronBackward)
                }
            }
            if !toolState.inDragMode {
                undoButton()
            }
            title()
        }
#endif
        
#if os(macOS)
        ToolbarItemGroup(placement: .cancellationAction) {
            SettingsButton(useDefaultLabel: true) {
                Label(.localizable(.settingsName), systemSymbol: .gear)
                    .labelStyle(.iconOnly)
            }
        }
#endif
        
        ToolbarItemGroup(placement: .confirmationAction) {
#if os(iOS)
            applePencilToggle()
#endif
            
            FileHistoryButton()
            
            Button {
                do {
                    if let file = fileState.currentFile {
                        self.sharedFile = try ExcalidrawFile(from: file.objectID, context: viewContext)
                    } else if let folder = fileState.currentLocalFolder,
                        let fileURL = fileState.currentLocalFile {
                        try folder.withSecurityScopedURL { _ in
                            self.sharedFile = try ExcalidrawFile(contentsOf: fileURL)
                        }
                    } else if fileState.isTemporaryGroupSelected,
                              let fileURL = fileState.currentTemporaryFile {
                        self.sharedFile = try ExcalidrawFile(contentsOf: fileURL)
                    }
                } catch {
                    alertToast(error)
                }
                
            } label: {
                Label(.localizable(.export), systemSymbol: .squareAndArrowUp)
            }
            .help(.localizable(.export))
            .disabled(
                fileState.currentGroup?.groupType == .trash ||
                (fileState.currentFile == nil && fileState.currentLocalFile == nil && fileState.currentTemporaryFile == nil)
            )

            if #available(macOS 13.0, iOS 16.0, *), appPreference.inspectorLayout == .sidebar {
#if os(iOS)
                if !layoutState.isInspectorPresented {
                    Button {
                        layoutState.isInspectorPresented.toggle()
                    } label: {
                        Label(.localizable(.librariesTitle), systemSymbol: .sidebarRight)
                    }
                }
#endif
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
        if let file = fileState.currentFile {
            VStack(
                alignment: .leading
            ) {
                Text(file.name ?? String(localizable: .generalUntitled))
                    .font(.headline)
                Text(file.updatedAt?.formatted() ?? "Not modified")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        } else if let fileURL = fileState.currentLocalFile ?? fileState.currentTemporaryFile {
            let filename = fileURL.deletingPathExtension().lastPathComponent
            let updatedAt = (try? FileManager.default.attributesOfItem(atPath: fileURL.filePath))?[.modificationDate] as? Date
            VStack(
                alignment: .leading
            ) {
                Text(filename)
                    .font(.headline)
                Text(updatedAt?.formatted() ?? "Not modified")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
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
    var isPresented: Bool
    var placement: ToolbarPlacement
    
    init(isPresented: Bool, placement: ToolbarPlacement) {
        self.isPresented = isPresented
        self.placement = placement
    }
    
    func body(content: Content) -> some View {
        if #available(macOS 15.0, iOS 18.0, *) {
            content
                .toolbarVisibility(isPresented ? .automatic : .hidden, for: placement)
        } else {
            content
                .toolbar(isPresented ? .automatic : .hidden, for: placement)
        }
    }
}
#endif
