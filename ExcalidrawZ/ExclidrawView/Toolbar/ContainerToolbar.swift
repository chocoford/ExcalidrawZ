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
    @Environment(\.managedObjectContext) private var managedObjectContext
    @Environment(\.containerHorizontalSizeClass) private var containerHorizontalSizeClass
    @Environment(\.alertToast) private var alertToast
    
    @EnvironmentObject var appPreference: AppPreference
    @EnvironmentObject var layoutState: LayoutState
    @EnvironmentObject var fileState: FileState
    @EnvironmentObject var toolState: ToolState

    @State private var sharedFile: File?
    
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
        .toolbarBackground(.visible, for: .bottomBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .navigationBarTitleDisplayMode(.inline) // <- fix principal toolbar
#endif
        .modifier(ShareViewModifier(sharedFile: $sharedFile))
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
        ToolbarItemGroup(placement: containerHorizontalSizeClass == .regular ? .principal : .bottomBar) {
            ExcalidrawToolbar()
        }
#endif
        
        ToolbarItemGroup(placement: .navigation) {
            if #available(macOS 13.0, iOS 16.0, *), appPreference.sidebarLayout == .sidebar {
                
            } else if containerHorizontalSizeClass == .regular {
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
                // create
                Button {
                    do {
                        try fileState.createNewFile(context: managedObjectContext)
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
            if containerHorizontalSizeClass == .compact {
                Button {
                    fileState.currentFile = nil
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
                
            } label: {
                Label(.localizable(.settingsName), systemSymbol: .gear)
                    .labelStyle(.iconOnly)
            }
        }
#endif
        
        ToolbarItemGroup(placement: .confirmationAction) {
            
            FileHistoryButton()
            
            Button {
                self.sharedFile = fileState.currentFile
            } label: {
                Label(.localizable(.export), systemSymbol: .squareAndArrowUp)
            }
            .help(.localizable(.export))
            .disabled(fileState.currentGroup?.groupType == .trash)


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
                    AsyncButton {
                        try await excalidrawCore.performUndo()
                    } label: {
                        Label(.localizable(.generalButtonUndo), systemSymbol: .arrowUturnBackward)
                    }
                    AsyncButton {
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
                    AsyncButton {
                        try await excalidrawCore.performUndo()
                    } label: {
                        Label(.localizable(.generalButtonUndo), systemSymbol: .arrowUturnBackward)
                    }
                    .disabled(true)
                    AsyncButton {
                        try await excalidrawCore.performRedo()
                    } label: {
                        Label(.localizable(.generalButtonRedo), systemSymbol: .arrowUturnForward)
                    }
                } label: {
                    Label(.localizable(.generalButtonUndo), systemSymbol: .arrowUturnBackwardCircle)
                        .foregroundStyle(.gray)
                }
            } else if excalidrawCore.canUndo {
                AsyncButton {
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
                Text(file.name ?? "")
                    .font(.headline)
                Text(file.createdAt?.formatted() ?? "Not modified")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
