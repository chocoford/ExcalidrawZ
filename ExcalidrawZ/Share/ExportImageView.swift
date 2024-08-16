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
    
    
    @State private var image: NSImage? = nil
    @State private var loadingImage: Bool = false
    @State private var showFileExporter = false
    @State private var showShare: Bool = false
    @State private var fileName: String = ""
    @State private var copied: Bool = false
    @State private var hasError: Bool = false

    @State private var showBackButton = false

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
        .onAppear {
            Task {
                do {
                    try await exportState.requestExport(type: .image)
                } catch {
                    alertToast(error)
                }
            }
            showBackButton = true
        }
        .onDisappear {
            showBackButton = false
        }
    }
    
    @ViewBuilder
    private var content: some View {
        VStack {
            if let image = image, let url = exportState.url {
                thumbnailView(image, url: url)
                fileInfoView
                actionsView(url)
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
        .watchImmediately(of: exportState.status) { status in
            guard status == .finish else { return }
            guard let url = exportState.url else {
                hasError = true
                return
            }
            guard let image = NSImage(contentsOf: url)?.resizeWhileMaintainingAspectRatioToSize(size: .init(width: 200, height: 120)) else {
                hasError = true
                return
            }
            self.image = image
            fileName = url.lastPathComponent.components(separatedBy: ".").first ?? String(localizable: .newFileNamePlaceholder)
        }
        .onDisappear {
            if let url = exportState.url {
                try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
            }
            exportState.status = .notRequested
            hasError = false
        }
    }
    
    
    @ViewBuilder private func thumbnailView(_ image: NSImage, url: URL) -> some View {
        DragableImageView(
            image: image,
            sourceURL: url
        )
        .frame(width: 200, height: 120, alignment: .center)
    }
    
    @ViewBuilder private var fileInfoView: some View {
        // File name
        TextField("", text: $fileName)
            .padding(.horizontal, 48)
            .textFieldStyle(.roundedBorder)
    }
    
    @ViewBuilder
    private func actionsView(_ url: URL) -> some View {
        HStack {
            Spacer()
            Button {
                if let image = NSImage(contentsOf: url) {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.writeObjects([image])
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
            }
            
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
            
            Spacer()
        }
        .fileExporter(isPresented: $showFileExporter,
                      document: ImageFile(url),
                      contentType: .image,
                      defaultFilename: fileName + ".png",
                      onCompletion: { result in
            switch result {
                case .success(let success):
                    print(success)
                case .failure(let failure):
//                    store.send(.setError(.unexpected(.init(failure))))
                    break
            }
//            self.store.send(.dismiss)
        })
    }
}

struct ImageFile: FileDocument {
    enum ImageFileError: Error {
        case initFailed
        case makeFileWrapperFailed
    }
    
    static var readableContentTypes = [UTType.image]

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
//struct ExportImageView_Previews: PreviewProvider {
//    static var previews: some View {
//        ExportImageView(
//            store: .init(initialState: .init(
//                url: URL(string: "https://testres.trickle.so/upload/avatars/agents/fba0556877814fe6866c97f9813b6ad4_8f2a9057-681a-4a27-96ed-9d0c5696b941.png")!,
//                download: .init()
//            )) {
//                ExportImageStore()
//            }
//        )
//    }
//}
#endif
