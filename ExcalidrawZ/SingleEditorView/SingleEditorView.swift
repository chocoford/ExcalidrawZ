//
//  SingleEditorView.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 2024/10/3.
//

import SwiftUI
import UniformTypeIdentifiers

import ChocofordUI

#if os(macOS)
struct SingleEditorView: View {
    @Environment(\.alertToast) var alertToast
    
    @EnvironmentObject var appPreference: AppPreference
    @EnvironmentObject var layoutState: LayoutState
    
    @Binding var fileDocument: ExcalidrawFile
    var fileURL: URL?
    var shouldAdjustWindowSize: Bool
    
    var fileType: UTType {
        guard let url = fileURL else { return .excalidrawFile }
        let lastPathComponent = url.lastPathComponent
        
        if lastPathComponent.hasSuffix(".excalidraw.png") {
            return .excalidrawPNG
        } else if lastPathComponent.hasSuffix(".excalidraw.svg") {
            return .excalidrawSVG
        } else {
            return UTType(filenameExtension: url.pathExtension) ?? .excalidrawFile
        }
    }
    
    
    
    init(config: FileDocumentConfiguration<ExcalidrawFile>, shouldAdjustWindowSize: Bool) {
        self._fileDocument = config.$document
        self.fileURL = config.fileURL
        self.shouldAdjustWindowSize = shouldAdjustWindowSize
     }
    
    @StateObject private var fileState = FileState()
    @StateObject private var exportState = ExportState()
    @StateObject private var toolState = ToolState()
    
    @State private var isLoading = true
    @State private var isProgressViewPresented = true
#if canImport(AppKit)
    @State private var window: NSWindow?
#elseif canImport(UIKit)
    @State private var window: UIWindow?
#endif


    var body: some View {
        ZStack {
            if #available(macOS 14.0, *), appPreference.inspectorLayout == .sidebar {
                content()
                    .inspector(isPresented: $layoutState.isInspectorPresented) {
                        LibraryView()
                            .inspectorColumnWidth(min: 240, ideal: 250, max: 300)
                    }
            } else {
                content()
                HStack {
                    Spacer()
                    if layoutState.isInspectorPresented {
                        LibraryView()
                            .frame(minWidth: 240, idealWidth: 250, maxWidth: 300)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .background {
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(.regularMaterial)
                                    .shadow(radius: 4)
                            }
                            .transition(.move(edge: .trailing))
                    }
                }
                .animation(.easeOut, value: layoutState.isInspectorPresented)
                .padding(.top, 10)
                .padding(.horizontal, 10)
                .padding(.bottom, 40)
            }
        }
        .environmentObject(fileState)
        .environmentObject(exportState)
        .environmentObject(toolState)
        .environmentObject(layoutState)
        .bindWindow($window)
        .onChange(of: window) { newValue in
            if let window = newValue, shouldAdjustWindowSize {
                let origin = window.frame.origin
                let originalSize = window.frame.size
                let newSize = CGSize(width: 1200, height: 650)
                window.setFrame(
                    NSRect(
                        origin: CGPoint(
                            x: origin.x - (newSize.width - originalSize.width) / 2,
                            y: origin.y - (newSize.height - originalSize.height) / 2
                        ),
                        size: newSize
                    ),
                    display: true,
                    animate: true
                )
            }
        }
        .onAppear {
            print("files count: \(self.fileDocument.files.count)")
            print(fileType)
        }
    }
    
    @MainActor @ViewBuilder
    private func content() -> some View {
        ZStack {
            ExcalidrawView(
                file: $fileDocument,
                savingType: fileType,
                isLoadingPage: $isLoading
            ) { error in
                alertToast(error)
                print(error)
            }
            .toolbar(content: toolbar)
            .opacity(isProgressViewPresented ? 0 : 1)
            .preferredColorScheme(appPreference.excalidrawAppearance.colorScheme)
            .onChange(of: isLoading, debounce: 1) { newVal in
                isProgressViewPresented = newVal
            }
            if isProgressViewPresented {
                VStack {
                    ProgressView()
                        .progressViewStyle(.circular)
                    Text(.localizable(.webViewLoadingText))
                }
            }
        }
        .animation(.default, value: isProgressViewPresented)
    }
    
    @MainActor @ToolbarContentBuilder
    private func toolbar() -> some ToolbarContent {
        ToolbarItemGroup(placement: .status) {
            if #available(macOS 13.0, *) {
                ExcalidrawToolbar()
                .padding(.vertical, 2)
            } else {
                ExcalidrawToolbar()
                    .offset(y: layoutState.isExcalidrawToolbarDense ? 0 : 6)
            }
        }
        
        ToolbarItemGroup(placement: .automatic) {
            Button {
                importToExcalidrawZ()
            } label: {
                Text("Import to ExcalidrawZ")
            }
            
            if #available(macOS 13.0, *), appPreference.inspectorLayout == .sidebar { } else {
                Button {
                    layoutState.isInspectorPresented.toggle()
                } label: {
                    Label("Library", systemSymbol: .sidebarRight)
                }
            }
        }
    }
    
    private func importToExcalidrawZ() {
        guard let fileURL,
              let url = URL(string: "excalidrawz://MainWindowGroup") else {
            return
        }
        let mainWindow = NSApp.windows.first(where: {$0.tabbingIdentifier.contains("WindowGroup")})
        NSApp.sendAction(#selector(NSDocument.save(_:)), to: nil, from: nil)
        self.window?.close()
        Task.detached {
            do {
                // NOT GOOD
                try await Task.sleep(nanoseconds: UInt64(1e+6 * 400))
                try await fileState.importFile(fileURL, to: .default)
                await MainActor.run {
                    if let mainWindow {
                        mainWindow.makeKeyAndOrderFront(nil)
                    } else {
                        NSWorkspace.shared.open(url)
                    }
                    NotificationCenter.default.post(
                        name: .didImportToExcalidrawZ,
                        object: fileState.currentFile?.id
                    )
                }
            } catch {
                await alertToast(error)
            }
        }
    }
}
#endif
//#Preview {
//    SingleEditorView(file: .constant(.preview))
//}
