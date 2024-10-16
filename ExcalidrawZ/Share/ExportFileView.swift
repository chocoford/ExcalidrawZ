//
//  ExportFileView.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 2023/8/8.
//

import SwiftUI
import ChocofordUI
import UniformTypeIdentifiers

@available(*, deprecated, message: "Use ExcalidrawFile instead")
struct ExcalidrawFileTransferable {}
struct ExportFileView: View {
    @Environment(\.managedObjectContext) var viewContext
    @Environment(\.dismiss) var mordenDismiss
    @Environment(\.alertToast) var alertToast
    
    var file: File
    private var _dismissAction: (() -> Void)?
    
    init(file: File, dismissAction: (() -> Void)? = nil) {
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
    
    @State private var showBackButton = false
    
    
    
    var body: some View {
        Center {
            if #available(macOS 13.0, *), let file = try? ExcalidrawFile(from: file.objectID, context: viewContext) {
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
            actionsView()
        }
        .overlay(alignment: .topLeading) {
            if showBackButton {
                Button {
                    dismiss()
                } label: {
                    Image(systemSymbol: .chevronLeft)
                }
                .transition(
                    .offset(x: -10).combined(with: .fade)
                )
            }
        }
        .animation(.default, value: showBackButton)
        .padding()
        .onAppear {
            saveFileToTemp()
            showBackButton = true
            fileName = file.name ?? String(localizable: .newFileNamePlaceholder)
            if let data = file.content {
                fileDocument = try? ExcalidrawFile(data: data)
            }
        }
        .onDisappear {
            showBackButton = false
        }
    }
    
    @ViewBuilder
    private func actionsView() -> some View {
        HStack {
            Spacer()
            Button {
                NSPasteboard.general.clearContents()
                if let url = fileURL,
                   let url = (url as NSURL).fileReferenceURL() as NSURL? {
                    NSPasteboard.general.writeObjects([url])
                    NSPasteboard.general.setString(url.relativeString, forType: .fileURL)
                    NSPasteboard.general.setData(file.content, forType: .fileContents)
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
//                if fileDocument != nil {
                    showFileExporter = true
//                }
            } label: {
                Label(.localizable(.exportActionSave), systemSymbol: .squareAndArrowDown)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
            }
            
            if #available(macOS 13.0, *),
               let url = fileURL {
                ShareLink(item: url) {
                    Label("Share", systemImage: "square.and.arrow.up")
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                }
            } else {
                Button {
                    self.showShare = true
                } label: {
                    Label("Share", systemImage: "square.and.arrow.up")
                        .padding(.horizontal, 6)
                }
                .background(SharingsPicker(
                    isPresented: $showShare,
                    sharingItems: fileURL != nil ? [fileURL!] : []
                ))
            }
            
            Spacer()
        }
        .fileExporter(
            isPresented: $showFileExporter,
            document: fileDocument,
            contentType: .excalidrawFile,
            defaultFilename: fileName
        ) { result in
            switch result {
                case .success:
                    alertToast(.init(displayMode: .hud, type: .complete(.green), title: "Saved"))
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
            if #available(macOS 13.0, *) {
                fileManager.createFile(atPath: url.path(percentEncoded: false), contents: file.content)
            } else {
                fileManager.createFile(atPath: url.standardizedFileURL.path, contents: file.content)
            }
            fileURL = url
        } catch {
            alertToast(error)
        }
    }
}

#if DEBUG
//#Preview {
//    ExportFileView(
//        store: .init(initialState: .init(file: .preview)) {
//            ExportFileStore()
//        }
//    )
//}
#endif
