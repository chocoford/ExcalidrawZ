//
//  ExportFileView.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 2023/8/8.
//

import SwiftUI
import ChocofordUI
import UniformTypeIdentifiers

struct ExportFileView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.managedObjectContext) var viewContext
    @Environment(\.dismiss) var mordenDismiss
    @Environment(\.alertToast) var alertToast
    
    var file: ExcalidrawFile
    private var _dismissAction: (() -> Void)?
    
    init(file: ExcalidrawFile, dismissAction: (() -> Void)? = nil) {
        self.file = file
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
        Center {
#if canImport(AppKit)
            if #available(macOS 13.0, *) {
                Image(nsImage: NSWorkspace.shared.icon(for: .excalidrawFile))
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(height: 80)
                    .draggable(file)
                    .padding()
            } else {
                Image(nsImage: NSWorkspace.shared.icon(for: .excalidrawFile))
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(height: 80)
                    .padding()
            }
#else
            Image(systemSymbol: .docText)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(height: 80)
                .padding()
#endif
            actionsView()
        }
        .modifier(ShareSubViewBackButtonModifier(dismiss: dismiss))
        .padding(horizontalSizeClass == .compact ? 0 : 20)
        .onAppear {
            saveFileToTemp()
            fileName = file.name ?? String(localizable: .newFileNamePlaceholder)
            do {
                fileDocument = file
                try fileDocument?.syncFiles(context: viewContext)
            } catch {
                alertToast(error)
            }
        }
    }
    
    @ViewBuilder
    private func actionsView() -> some View {
        HStack {
            Spacer()
            Button {
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
                    withAnimation {
                        copied = true
                    }
                    Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { _ in
                        withAnimation {
                            copied = false
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
        .modernButtonStyle(shape:. modern)
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
    
    
    func saveFileToTemp() {
        do {
            let fileManager: FileManager = FileManager.default
            let directory: URL = try getTempDirectory()
            let fileExtension = "excalidraw"
            let filename = (file.name ?? String(localizable: .newFileNamePlaceholder)) + ".\(fileExtension)"
            let url = directory.appendingPathComponent(filename, conformingTo: .fileURL)
            if fileManager.fileExists(atPath: url.absoluteString) {
                try fileManager.removeItem(at: url)
            }
            
            var file = file
            try file.syncFiles(context: viewContext)
            guard let fileData = file.content else {
                struct NoContentError: LocalizedError {
                    var errorDescription: String? {
                        "The file has no data."
                    }
                }
                throw NoContentError()
            }

            if #available(macOS 13.0, *) {
                fileManager.createFile(atPath: url.path(percentEncoded: false), contents: fileData)
            } else {
                fileManager.createFile(atPath: url.standardizedFileURL.path, contents: fileData)
            }
            fileURL = url
        } catch {
            alertToast(error)
        }
    }
}
