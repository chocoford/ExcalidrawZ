//
//  SingleEditorView.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 2024/10/3.
//

import SwiftUI
import UniformTypeIdentifiers

import ChocofordUI

struct SingleEditorView: View {
    @Environment(\.alertToast) var alertToast
    
    @EnvironmentObject var appPreference: AppPreference
    
    @Binding var fileDocument: ExcalidrawFile
    var fileURL: URL?
    
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
    
    init(config: FileDocumentConfiguration<ExcalidrawFile>) {
        self._fileDocument = config.$document
        self.fileURL = config.fileURL
     }
    
    @StateObject private var fileState = FileState()
    @StateObject private var exportState = ExportState()
    @StateObject private var toolState = ToolState()
    
    @State private var isLoading = true
    @State private var isProgressViewPresented = true
    
    @State private var window: NSWindow?
    
    @State private var isExcalidrawToolbarDense: Bool = false
    @State private var isInspectorPresented: Bool = false

    var body: some View {
        ZStack {
            if #available(macOS 14.0, *), appPreference.inspectorLayout == .sidebar {
                content()
                    .inspector(isPresented: $isInspectorPresented) {
                        LibraryView(isPresented: $isInspectorPresented)
                            .inspectorColumnWidth(min: 240, ideal: 250, max: 300)
                    }
            } else {
                content()
                HStack {
                    Spacer()
                    if isInspectorPresented {
                        LibraryView(isPresented: $isInspectorPresented)
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
                .animation(.easeOut, value: isInspectorPresented)
                .padding(.top, 10)
                .padding(.horizontal, 10)
                .padding(.bottom, 40)
            }
        }
        .environmentObject(fileState)
        .environmentObject(exportState)
        .environmentObject(toolState)
        .bindWindow($window)
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
                ExcalidrawToolbar(
                    isInspectorPresented: .constant(false),
                    isSidebarPresented: .constant(false),
                    isDense: $isExcalidrawToolbarDense
                )
                .padding(.vertical, 2)
            } else {
                ExcalidrawToolbar(
                    isInspectorPresented: .constant(false),
                    isSidebarPresented: .constant(false),
                    isDense: $isExcalidrawToolbarDense
                )
                .offset(y: isExcalidrawToolbarDense ? 0 : 6)
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
                    isInspectorPresented.toggle()
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
                try await fileState.importFile(fileURL, toDefaultGroup: true)
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

//#Preview {
//    SingleEditorView(file: .constant(.preview))
//}
