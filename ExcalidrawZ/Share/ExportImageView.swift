//
//  ExportImageView.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 2023/4/3.
//

import SwiftUI
import ChocofordUI
import UniformTypeIdentifiers
import WebKit

struct ExportImageView: View {
    @Environment(\.dismiss) var mordenDismiss
    @Environment(\.alertToast) var alertToast
    
    @EnvironmentObject var exportState: ExportState
    
    private var _dismissAction: (() -> Void)?
    init(dismissAction: (() -> Void)? = nil) {
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
    
    @State private var exportedImageData: ExportedImageData?
    @State private var image: NSImage?
    @State private var loadingImage: Bool = false
    @State private var showFileExporter = false
    @State private var showShare: Bool = false
    @State private var fileName: String = ""
    @State private var copied: Bool = false
    @State private var hasError: Bool = false

    @State private var showBackButton = false
    
    @State private var keepEditable = false
    @State private var imageType: Int = 0
    
    var exportType: UTType {
        switch imageType {
            case 0:
                return keepEditable ? .excalidrawPNG : .png
            case 1:
                return keepEditable ? .excalidrawSVG : .svg
            default:
                return .image
        }
    }
    
    var body: some View {
        VStack {
            Center {
                content
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
        }
        .padding()
        .onChange(of: keepEditable) { newValue in
            exportImageData()
        }
        .onChange(of: imageType) { newValue in
            exportImageData()
        }
        .onAppear {
            if isPreview {
                self.image = NSImage(named: "Layout-Inspector-Floating")
                exportState.url = URL(string: "https://www.google.com")!
                return
            }
            exportImageData(initial: true)
            showBackButton = true
        }
        .onDisappear {
            showBackButton = false
        }
    }
    
    @MainActor @ViewBuilder
    private var content: some View {
        VStack {
            if let image, let exportedImageData {
                thumbnailView(image, url: exportedImageData.url)
                fileInfoView
                actionsView(exportedImageData.url)
            } else if hasError {
                Text(.localizable(.exportImageLoadingError))
                    .foregroundColor(.red)
            } else {
                ProgressView()
                Text(.localizable(.exportImageLoading))
                
                Button {
                    dismiss()
                } label: {
                    Text(.localizable(.exportImageLoadingButtonCancel))
                }
                .offset(y: 40)
            }
        }
        .onDisappear {
            if let url = exportedImageData?.url {
                try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
            }
            exportState.status = .notRequested
            hasError = false
        }
    }
    
    
    @MainActor @ViewBuilder
    private func thumbnailView(_ image: NSImage, url: URL) -> some View {
        DragableImageView(
            image: image,
            sourceURL: url
        )
        .scaledToFit()
        .frame(width: 200, height: 120, alignment: .center)
    }
    

    @MainActor @ViewBuilder
    private var fileInfoView: some View {
        VStack {
            HStack(alignment: .bottom, spacing: 4) {
                // File name
                TextField("", text: $fileName)
                    .textFieldStyle(.roundedBorder)
                
                HStack(alignment: .bottom, spacing: 0) {
                    if keepEditable {
                        Text(".excalidraw")
                    }
                    HStack(alignment: .bottom, spacing: -2) {
                        Text(".")
                        Picker(selection: $imageType) {
                            Text("png").tag(0)
                            Text("svg").tag(1)
                        } label: {}
                            .pickerStyle(.menu)
                        //                    .menuStyle(.button)
                            .buttonStyle(.borderless)
                            .menuIndicator(.visible)
                    }
                }
            }
            HStack {
                Spacer()
                Toggle("Keep editable", isOn: $keepEditable)
                    .toggleStyle(.checkboxStyle)
            }
        }
        .animation(.default, value: keepEditable)
        .padding(.horizontal, 48)
    }
    
    @ViewBuilder
    private func actionsView(_ url: URL) -> some View {
        HStack {
            Button {
                NSPasteboard.general.clearContents()
                switch self.imageType {
                    case 0:
                        if let image = NSImage(contentsOf: url) {
                            NSPasteboard.general.writeObjects([image])
                        } else {
                            return
                        }
                    case 1:
                        if let string = String(data: (try? Data(contentsOf: url)) ?? Data(), encoding: .utf8) {
                            NSPasteboard.general.writeObjects([string as NSString])
                        } else {
                            return
                        }
                    default:
                        break
                }
                withAnimation {
                    copied = true
                }
                Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { _ in
                    withAnimation {
                        copied = false
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
                        Label(.localizable(.exportActionCopy), systemSymbol: .docOnClipboard)
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
            
            if #available(macOS 13.0, *) {
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
                .background(
                    SharingsPicker(
                        isPresented: $showShare,
                        sharingItems: [url]
                    )
                )
            }
        }
        .controlSize(.regular)
        .fileExporter(
            isPresented: $showFileExporter,
            document: ImageFile(url),
            contentType: exportType,
            defaultFilename: fileName
        ) { result in
            switch result {
                case .success(let success):
                    print(success)
                case .failure(let failure):
                    alertToast(failure)
            }
        }
    }
    
    
    private func exportImageData(initial: Bool = false) {
        Task.detached {
            do {
                if initial {
                    let imageData = try await exportState.exportCurrentFileToImage(
                        type: .png,
                        embedScene: false
                    )
                    await MainActor.run {
                        self.image = NSImage(data: imageData.data)?.resizeWhileMaintainingAspectRatioToSize(size: .init(width: 200, height: 120))
                        self.exportedImageData = imageData
                        self.fileName = imageData.name
                    }
                } else {
                    let imageData = try await exportState.exportCurrentFileToImage(
                        type: self.imageType == 0 ? .png : .svg,
                        embedScene: self.keepEditable
                    )
                    await MainActor.run {
                        self.exportedImageData = imageData
                    }
                }
            } catch {
                await alertToast(error)
            }
        }
    }
}

struct ImageFile: FileDocument {
    enum ImageFileError: Error {
        case initFailed
        case makeFileWrapperFailed
    }
    
    static var readableContentTypes = [UTType.image]
    static var writableContentTypes: [UTType] {
        [.excalidrawPNG, .excalidrawSVG, .png, .svg]
    }

    // by default our document is empty
    var url: URL

    init(_ url: URL) {
        self.url = url
    }
    
    // this initializer loads data that has been saved previously
    init(configuration: ReadConfiguration) throws {
        
//        if let data = configuration.file.regularFileContents, let img = NSImage(data: data) {
//            image = img
//        } else {
        throw ImageFileError.initFailed
//        }
    }

    // this will be called when the system wants to write our data to disk
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let fileWrapper = try FileWrapper(url: url)
//        fileWrapper.filename = fileName
//        fileWrapper.fileAttributes[FileAttributeKey.type.rawValue] = "png"
        return fileWrapper
    }
}

#if DEBUG
#Preview {
    ExportImageView()
        .environmentObject(ExportState())
}
#endif
