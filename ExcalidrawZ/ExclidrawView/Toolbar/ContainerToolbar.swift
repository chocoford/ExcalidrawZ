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
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.alertToast) private var alertToast
    
    @EnvironmentObject var appPreference: AppPreference
    @EnvironmentObject var layoutState: LayoutState
    @EnvironmentObject var fileState: FileState
    @EnvironmentObject var toolState: ToolState

    @State private var sharedFile: File?
    @State private var isFileHistoryPresented = false
    
    func body(content: Content) -> some View {
        ZStack {
            if horizontalSizeClass == .compact {
                content
#if os(iOS)
                    .navigationBarBackButtonHidden()
#endif
            } else {
                content
            }
        }
        .toolbar(content: toolbarContent)
#if os(iOS)
        .toolbarBackground(.visible, for: .bottomBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .navigationBarTitleDisplayMode(.inline) // <- fix principal toolbar
#endif
        .modifier(ShareViewModifier(sharedFile: $sharedFile))
        .modifier(FileHistoryModifier(isPresented: $isFileHistoryPresented))
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
        ToolbarItemGroup(placement: horizontalSizeClass == .regular ? .principal : .bottomBar) {
            ExcalidrawToolbar()
        }
#endif
        
        ToolbarItemGroup(placement: .navigation) {
            if #available(macOS 13.0, iOS 16.0, *), appPreference.sidebarLayout == .sidebar {
                
            } else if horizontalSizeClass == .regular {
                Button {
                    layoutState.isSidebarPresented.toggle()
                } label: {
                    Label("Sidebar", systemSymbol: .sidebarLeft)
                }
            }
            
#if os(macOS)            
            title()
#endif

            if #available(macOS 13.0, iOS 16.0, *) { } else {
                // create
                Button {
                    do {
                        try fileState.createNewFile()
                    } catch {
                        alertToast(error)
                    }
                } label: {
                    Label(.localizable(.createNewFile), systemSymbol: .squareAndPencil)
                }
                .help(.localizable(.createNewFile))
                .disabled(fileState.currentGroup?.groupType == .trash)
            }
        }
        
#if os(iOS)
        ToolbarItemGroup(placement: .topBarLeading) {
            if horizontalSizeClass == .compact {
                Button {
                    fileState.currentFile = nil
                } label: {
                    Label("Back", systemSymbol: .chevronBackward)
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
                
            } label: {
                Label("Settings", systemSymbol: .gear)
                    .labelStyle(.iconOnly)
            }
        }
#endif
        
        ToolbarItemGroup(placement: .confirmationAction) {
            if let currentFile = fileState.currentFile {
                Button {
                    isFileHistoryPresented.toggle()
                } label: {
                    Label(.localizable(.checkpoints), systemSymbol: .clockArrowCirclepath)
                }
                .disabled(fileState.currentGroup?.groupType == .trash)
                .help(.localizable(.checkpoints))
            }

            Button {
                self.sharedFile = fileState.currentFile
            } label: {
                Label(.localizable(.export), systemSymbol: .squareAndArrowUp)
            }
            .help(.localizable(.export))
            .disabled(fileState.currentGroup?.groupType == .trash)


            if #available(macOS 13.0, iOS 16.0, *), appPreference.inspectorLayout == .sidebar { } else {
                Button {
                    layoutState.isInspectorPresented.toggle()
                } label: {
                    Label("Library", systemSymbol: .sidebarRight)
                }
            }
        }
    }
    
    @MainActor @ViewBuilder
    private func undoButton() -> some View {
        if let excalidrawCore = fileState.excalidrawWebCoordinator {
            if excalidrawCore.canUndo, excalidrawCore.canRedo {
                Menu {
                    AsyncButton {
                        try await excalidrawCore.performUndo()
                    } label: {
                        Label("Undo", systemSymbol: .arrowUturnBackward)
                    }
                    AsyncButton {
                        try await excalidrawCore.performRedo()
                    } label: {
                        Label("Redo", systemSymbol: .arrowUturnForward)
                    }
                } label: {
                    Label("Undo", systemSymbol: .arrowUturnBackwardCircle)
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
                    AsyncButton {
                        try await excalidrawCore.performUndo()
                    } label: {
                        Label("Undo", systemSymbol: .arrowUturnBackward)
                    }
                    .disabled(true)
                    AsyncButton {
                        try await excalidrawCore.performRedo()
                    } label: {
                        Label("Redo", systemSymbol: .arrowUturnForward)
                    }
                } label: {
                    Label("Undo", systemSymbol: .arrowUturnBackwardCircle)
                        .foregroundStyle(.gray)
                }
            } else if excalidrawCore.canUndo {
                AsyncButton {
                    try await excalidrawCore.performUndo()
                } label: {
                    Label("Undo", systemSymbol: .arrowUturnBackwardCircle)
                }
            } else {
                Button { } label: {
                    Label("Undo", systemSymbol: .arrowUturnBackwardCircle)
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
                Text(file.name ?? "")
                    .font(.headline)
                Text(file.createdAt?.formatted() ?? "Not modified")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
