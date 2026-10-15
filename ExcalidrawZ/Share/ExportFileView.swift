//
//  ExportFileView.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 2023/8/8.
//

import SwiftUI
import CoreData
import SwiftyAlert
import ChocofordUI
import UniformTypeIdentifiers

struct ExportFileView: View {
    @Environment(\.managedObjectContext) var viewContext
    @Environment(\.dismiss) var mordenDismiss
    @Environment(\.alertToast) var alertToast
    
    var file: ExcalidrawFile
    private var _dismissAction: (() -> Void)?
    
    init(file: ExcalidrawFile, dismissAction: (() -> Void)? = nil) {
        self.file = file
        self._fileName = State(
            initialValue: file.name ?? String(localizable: .newFileNamePlaceholder)
        )
        if let dismissAction {
            self._dismissAction = dismissAction
        }
    }
    
    func dismiss() {
        if let _dismissAction {
            _dismissAction()
        } else {
            mordenDismiss()
        }
    }
    
    @State private var fileURL: URL?
    
    @State private var loadingImage: Bool = false
    @State private var showFileExporter = false
    @State private var showShare: Bool = false
    @State private var fileName: String = ""
    @State private var copied: Bool = false
    
    @State private var fileContentString: String = ""
    @State private var fileDocument: ExcalidrawFile?
        
    var body: some View {
        ShareSubViewContainer(dismiss: dismiss) {
            SwiftUI.Group {
#if os(macOS)
                Center {
                    if #available(macOS 13.0, *) {
                        Image(nsImage: NSWorkspace.shared.icon(for: .excalidrawFile))
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(height: 80)
                            .onDrag {
                                makeFileDragItemProvider()
                            }
                            .padding()
                    } else {
                        Image(nsImage: NSWorkspace.shared.icon(for: .excalidrawFile))
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(height: 80)
                            .padding()
                    }
                    actionsView()
                }
#else
                VStack(spacing: 20) {
                    VStack(spacing: 4) {
                        Image(systemSymbol: .docText)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(height: 80)
                            .padding()
                        Text(fileName + ".excalidraw")
                    }
                    actionsView()
                }
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            dismiss()
                        } label: {
                            Image(systemSymbol: .xmark)
                        }
                    }
                }
#endif
            }
        }
        .task {
            do {
                var fileDocument = file
                try await fileDocument.syncFiles(context: viewContext)
                try fileDocument.prepareContentForExport(fileName: fileName)
                await MainActor.run {
                    self.fileDocument = fileDocument
                }
                try await saveFileToTemp(fileDocument)
            } catch {
                alertToast(error)
            }
        }
    }

#if os(macOS)
    @available(macOS 13.0, *)
    private func makeFileDragItemProvider() -> NSItemProvider {
        do {
            let url = try file.fileURL()
            return NSItemProvider(
                item: url.dataRepresentation as NSData,
                typeIdentifier: UTType.fileURL.identifier
            )
        } catch {
            alertToast(error)
            return NSItemProvider()
        }
    }
#endif
    
    @ViewBuilder
    private func actionsView() -> some View {
        HStack {
            Spacer()
            AsyncButton {
#if canImport(AppKit)
                NSPasteboard.general.clearContents()
#endif

                if let url = fileURL,
                   let url = (url as NSURL).fileReferenceURL() as NSURL? {
#if canImport(AppKit)
                    NSPasteboard.general.writeObjects([url])
                    NSPasteboard.general.setString(url.relativeString, forType: .fileURL)
                    NSPasteboard.general.setData(file.content, forType: .fileContents)
#elseif canImport(UIKit)
                    UIPasteboard.general.setObjects([url])
#endif
                    await MainActor.run {
                        withAnimation {
                            copied = true
                        }
                        Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { _ in
                            withAnimation {
                                copied = false
                            }
                        }
                    }
                }
            } label: {
                if copied {
                    Label(.localizable(.exportActionCopied), systemSymbol: .checkmark)
                        .padding(.horizontal, 6)
                } else {
                    if #available(macOS 13.0, *) {
                        Label(.localizable(.exportActionCopy), systemSymbol: .clipboard)
                            .padding(.horizontal, 6)
                    } else {
                        // Fallback on earlier versions
                        Label(.localizable(.exportActionCopy), systemSymbol: .docOnDoc)
                            .padding(.horizontal, 6)
                    }
                }
            }
            .disabled(copied)
            
            Button {
                showFileExporter = true
            } label: {
                Label(.localizable(.exportActionSave), systemSymbol: .squareAndArrowDown)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
            }
            
            if #available(macOS 13.0, *),
               let url = fileURL {
                ShareLink(item: url) {
                    Label(.localizable(.exportActionShare), systemSymbol: .squareAndArrowUp)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                }
            } else {
                Button {
                    self.showShare = true
                } label: {
                    Label(.localizable(.exportActionShare), systemSymbol: .squareAndArrowUp)
                        .padding(.horizontal, 6)
                }
                .background(SharingsPicker(
                    isPresented: $showShare,
                    sharingItems: fileURL != nil ? [fileURL!] : []
                ))
            }
            
            Spacer()
        }
        .modernButtonStyle(style: .glass, shape: .modern)
        .fileExporter(
            isPresented: $showFileExporter,
            document: fileDocument,
            contentType: .excalidrawFile,
            defaultFilename: fileName
        ) { result in
            switch result {
                case .success:
                    alertToast(.init(displayMode: .hud, type: .complete(.green), title: String(localizable: .generalFileExporterSaved)))
                case .failure(let failure):
                    alertToast(failure)
            }
        }
    }
    
    
    private func saveFileToTemp(_ file: ExcalidrawFile) async throws {
        let fileManager: FileManager = FileManager.default
        let directory: URL = try getTempDirectory()
        let filename = fileName + ".excalidraw"
        let url = directory.appendingPathComponent(filename, conformingTo: .fileURL)
        if fileManager.fileExists(atPath: url.filePath) {
            try fileManager.removeItem(at: url)
        }

        guard let fileData = file.content else {
            struct NoContentError: LocalizedError {
                var errorDescription: String? {
                    "The file has no data."
                }
            }
            throw NoContentError()
        }

        try fileData.write(to: url, options: .atomic)
        await MainActor.run {
            fileURL = url
        }
    }
}
