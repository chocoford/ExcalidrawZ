//
//  SingleEditorView.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 2024/10/3.
//

import SwiftUI

import ChocofordUI

struct SingleEditorView: View {
    @Environment(\.alertToast) var alertToast
    
    @EnvironmentObject var appPreference: AppPreference
    
    @Binding var fileDocument: ExcalidrawFile
    var fileURL: URL?
    
    init(config: FileDocumentConfiguration<ExcalidrawFile>) {
        self._fileDocument = config.$document
        self.fileURL = config.fileURL
     }
    
    @StateObject private var fileState = FileState()
    @StateObject private var exportState = ExportState()
    @StateObject private var toolState = ToolState()
    
    @State private var isLoading = true
    @State private var isLoadingFile = false
    
    @State private var window: NSWindow?
    
    @State private var isExcalidrawToolbarDense: Bool = false
    
    var body: some View {
        ZStack {
            ExcalidrawView(
                file: $fileDocument,
                isLoadingPage: $isLoading,
                isLoadingFile: $isLoadingFile
            ) { error in
                alertToast(error)
                print(error)
            }
            .opacity(isLoading ? 0 : 1)
            .preferredColorScheme(appPreference.excalidrawAppearance.colorScheme)
            
            if isLoading {
                VStack {
                    ProgressView()
                        .progressViewStyle(.circular)
                    Text(.localizable(.webViewLoadingText))
                }
            }
        }
        .toolbar {
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
            
            ToolbarItem(placement: .automatic) {
                Button {
                    importToExcalidrawZ()
                } label: {
                    Text("Import to ExcalidrawZ")
                }
            }
        }
        .environmentObject(fileState)
        .environmentObject(exportState)
        .environmentObject(toolState)
        .bindWindow($window)
        .onAppear {
            print("files count: \(self.fileDocument.files.count)")
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
