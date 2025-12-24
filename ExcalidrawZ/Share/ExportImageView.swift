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
#if canImport(AppKit)
    typealias PlatformImage = NSImage
#elseif canImport(UIKit)
    typealias PlatformImage = UIImage
#endif
    @Environment(\.dismiss) var mordenDismiss
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    @Environment(\.containerHorizontalSizeClass) var containerHorizontalSizeClass
    @Environment(\.alertToast) var alertToast
    
    @EnvironmentObject var exportState: ExportState
    
    var elements: [ExcalidrawElement]
    
    private var _dismissAction: (() -> Void)?
    init(
        file: ExcalidrawFile,
        dismissAction: (() -> Void)? = nil
    ) {
        self.elements = file.elements
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
    @State private var image: PlatformImage?
    @State private var loadingImage: Bool = false
    @State private var showFileExporter = false
    @State private var showShare: Bool = false
    @State private var fileName: String = ""
    @State private var copied: Bool = false
    @State private var hasError: Bool = false

    @State private var keepEditable = false
    @State private var exportWithBackground = true
    @State private var imageType: Int = 0
    @State private var exportColorScheme: ColorScheme = .light
    
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
        SwiftUI.Group {
#if os(macOS)
            Center {
                content
            }
#else
            iOSContent()
#endif
        }
        .modifier(ShareSubViewBackButtonModifier(dismiss: dismiss))
        .padding(horizontalSizeClass == .compact ? 0 : 20)
        .onChange(of: keepEditable) { newValue in
            exportImageData()
        }
        .onChange(of: exportWithBackground) { newValue in
            exportImageData(initial: true)
        }
        .onChange(of: imageType) { newValue in
            exportImageData()
        }
        .onChange(of: exportColorScheme) { _ in
            exportImageData(initial: true)
        }
        .onChange(of: exportType) { _ in
            exportColorScheme = .light
        }
        .onAppear {
            if isPreview {
                self.image = .init(named: "Layout-Inspector-Floating")
                exportState.url = URL(string: "https://www.google.com")!
                exportedImageData = .init(name: "Preview", data: Data(), url: URL(string: "https://www.google.com")!)
                return
            }
            exportImageData(initial: true)
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
    
    
#if os(iOS)
    @MainActor @ViewBuilder
    private func iOSContent() -> some View {
        NavigationStack {
            Form {
                Section {
                    exportImageSettingItems()
                } header: {
                    if let image, let exportedImageData {
                        VStack {
                            thumbnailView(image, url: exportedImageData.url)
                                .frame(height: 200)
                                .padding(.vertical)
                            imageNameField()
                        }
                    } else if hasError {
                        Text(.localizable(.exportImageLoadingError))
                            .foregroundColor(.red)
                    } else {
                        VStack {
                            ProgressView()
                            Text(.localizable(.exportImageLoading))
                        }
                        .frame(height: 274)
                        .frame(maxWidth: .infinity)
                    }
                } footer: {
                    if let exportedImageData {
                        if containerHorizontalSizeClass == .compact {
                            VStack {
                                actionItems(exportedImageData.url)
                            }
                            .modernButtonStyle(style: .glass)
                        } else {
                            HStack {
                                Spacer()
                                HStack {
                                    actionItems(exportedImageData.url)
                                }
                                .modernButtonStyle(style: .glass)
                            }
                        }
                    }
                }
            }
            .scrollDisabled(true)
            .formStyle(.grouped)
            .navigationTitle(.localizable(.tipsShareDetailExportImageTitle))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemSymbol: .xmark)
                    }
                }
            }
        }
//        .toolbar {
//            ToolbarItemGroup(placement: .bottomBar) {
//
//            }
//        }
    }
#endif

    @MainActor @ViewBuilder
    private func thumbnailView(_ image: PlatformImage, url: URL) -> some View {
#if os(macOS)
        DragableImageView(
            image: image,
            sourceURL: url
        )
        .scaledToFit()
        .frame(width: 200, height: 120, alignment: .center)
#else
        Color.clear
            .overlay {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
            }
#endif

    }
    
    @MainActor @ViewBuilder
    private var fileInfoView: some View {
        VStack {
            imageNameField()
            
            HStack {
                exportImageSettingItems()
            }
            .controlSize(horizontalSizeClass == .compact ? .mini : .regular)
        }
        .font(horizontalSizeClass == .compact ? .footnote : .body)
        .animation(.default, value: keepEditable)
        .padding(.horizontal, 48)
    }
    
    
    @MainActor @ViewBuilder
    private func imageNameField() -> some View {
        HStack(alignment: .center, spacing: 4) {
            // File name
            Color.clear.frame(height: 30)
                .overlay {
                    TextField("", text: $fileName)
                        .textFieldStyle(.roundedBorder)
                }
            
            HStack(alignment: .bottom, spacing: 0) {
                if keepEditable {
                    Text(".excalidraw")
                        .lineLimit(1)
                        .frame(height: 20)
                        .padding(.bottom, 4)
                }
                HStack(alignment: .bottom, spacing: -8) {
                    Text(".").padding(.bottom, 4)

                    Picker(selection: $imageType) {
                        Text("png").tag(0)
                        Text("svg").tag(1)
                    } label: {}
                        .pickerStyle(.menu)
                    //                    .menuStyle(.button)
                        .buttonStyle(.borderless)
                        .menuIndicator(.visible)
                        .fixedSize()
                }
            }
        }
    }
    
    @MainActor @ViewBuilder
    private func exportImageSettingItems() -> some View {
        Picker(.localizable(.exportImagePickerColorSchemeLabel), selection: $exportColorScheme) {
            Text(.localizable(.generalColorSchemeLight)).tag(ColorScheme.light)
            Text(.localizable(.generalColorSchemeDark)).tag(ColorScheme.dark)
        }
//#if os(iOS)
//        .pickerStyle(.segmented)
//#endif
        .disabled(exportType != .png)

#if os(macOS)
        Toggle(.localizable(.exportImageToggleWithBackground), isOn: $exportWithBackground)
            .toggleStyle(.checkboxStyle)
#elseif os(iOS)
        Toggle(.localizable(.exportImageToggleWithBackground), isOn: $exportWithBackground)
            .toggleStyle(.switch)
#endif
        
#if os(macOS)
        Toggle(.localizable(.exportImageToggleEditable), isOn: $keepEditable)
            .toggleStyle(.checkboxStyle)
#elseif os(iOS)
        Toggle(.localizable(.exportImageToggleEditable), isOn: $keepEditable)
            .toggleStyle(.switch)
#endif
    }
    
    @ViewBuilder
    private func actionsView(_ url: URL) -> some View {
        HStack {
            actionItems(url)
        }
        .modernButtonStyle(size: .regular, shape: .modern)
        
    }
    
    @MainActor @ViewBuilder
    private func actionItems(_ url: URL) -> some View {
        Button {
#if canImport(AppKit)
            NSPasteboard.general.clearContents()
            switch self.imageType {
                case 0:
                    if let image = PlatformImage(contentsOf: url) {
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
#elseif canImport(UIKit)
            switch self.imageType {
                case 0:
                    if let image = PlatformImage(contentsOf: url) {
                        UIPasteboard.general.setObjects([image])
                    } else {
                        return
                    }
                case 1:
                    if let string = String(data: (try? Data(contentsOf: url)) ?? Data(), encoding: .utf8) {
                        UIPasteboard.general.setObjects([string as NSString])
                    } else {
                        return
                    }
                default:
                    break
            }
#endif
            
            withAnimation {
                copied = true
            }
            Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { _ in
                withAnimation {
                    copied = false
                }
            }
        } label: {
            ZStack {
                if copied {
                    Label(.localizable(.exportActionCopied), systemSymbol: .checkmark)
                        .padding(.horizontal, 6)
                } else {
                    if #available(macOS 13.0, iOS 16.0, *) {
                        Label(.localizable(.exportActionCopy), systemSymbol: .clipboard)
                            .padding(.horizontal, 6)
                    } else {
                        // Fallback on earlier versions
                        Label(.localizable(.exportActionCopy), systemSymbol: .docOnClipboard)
                            .padding(.horizontal, 6)
                    }
                }
            }
            .frame(maxWidth: containerHorizontalSizeClass == .compact ? .infinity : nil)
        }
        .disabled(copied)
        
        Button {
            showFileExporter = true
        } label: {
            Label(.localizable(.exportActionSave), systemSymbol: .squareAndArrowDown)
                .padding(.horizontal, 6)
                .padding(.vertical, 1)
                .frame(maxWidth: containerHorizontalSizeClass == .compact ? .infinity : nil)
        }
        .fileExporter(
            isPresented: $showFileExporter,
            document: ImageFile(url),
            contentType: exportType,// == .excalidrawPNG ? .png : exportType == .excalidrawSVG ? .svg : exportType,
            defaultFilename: fileName
        ) { result in
            switch result {
                case .success(let success):
                    print(success)
                case .failure(let failure):
                    alertToast(failure)
            }
        }
        
        if #available(macOS 13.0, iOS 16.0, *) {
            ShareLink(item: url) {
                Label(.localizable(.exportActionShare), systemSymbol: .squareAndArrowUp)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .frame(maxWidth: containerHorizontalSizeClass == .compact ? .infinity : nil)
            }
        } else {
            Button {
                self.showShare = true
            } label: {
                Label(.localizable(.exportActionShare), systemSymbol: .squareAndArrowUp)
                    .padding(.horizontal, 6)
                    .frame(maxWidth: containerHorizontalSizeClass == .compact ? .infinity : nil)
            }
            .background(
                SharingsPicker(
                    isPresented: $showShare,
                    sharingItems: [url]
                )
            )
        }
    }
    
    private func exportImageData(initial: Bool = false) {
        Task.detached {
            do {
                if initial {
                    await MainActor.run {
                        self.image = nil
                        self.exportedImageData = nil
                    }
                    let imageData = try await exportState.exportCurrentFileToImage(
                        type: .png,
                        embedScene: false,
                        withBackground: self.exportWithBackground,
                        colorScheme: self.exportColorScheme
                    )
                    await MainActor.run {
                        self.image = PlatformImage(data: imageData.data)?
                            .resizeWhileMaintainingAspectRatioToSize(size: .init(width: 200, height: 120))
                        self.exportedImageData = imageData
                        self.fileName = imageData.name
                    }
                } else {
                    let imageData = try await exportState.exportCurrentFileToImage(
                        type: self.imageType == 0 ? .png : .svg,
                        embedScene: self.keepEditable,
                        withBackground: self.exportWithBackground,
                        colorScheme: self.exportColorScheme
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
        throw ImageFileError.initFailed
    }

    // this will be called when the system wants to write our data to disk
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        print("contentType:" , configuration.contentType)
        print("url:" , url)
        let fileWrapper = try FileWrapper(regularFileWithContents: Data(contentsOf: url))
//        print(fileWrapper, fileWrapper.filename, fileWrapper.preferredFilename)
        return fileWrapper
    }
}
//print(url, fileWrapper.filename)
//        if let filename = fileWrapper.filename,
//           configuration.contentType == .excalidrawPNG || configuration.contentType == .excalidrawSVG {
//            let newFilename = String(
//                filename.prefix(filename.count - (configuration.contentType.preferredFilenameExtension?.count ?? 1) - 1)
//            )
//            fileWrapper.filename = newFilename
//            fileWrapper.preferredFilename = newFilename
//            print(newFilename, fileWrapper.fileAttributes)
//        }
// no permission
class ExcalidrawFileWrapper: FileWrapper {
    var isImage: Bool
    
    init(url: URL, isImage: Bool, options: FileWrapper.ReadingOptions = []) throws {
        self.isImage = isImage
        try super.init(url: url, options: options)
    }
    
    required init?(coder inCoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func write(to url: URL, options: FileWrapper.WritingOptions = [], originalContentsURL: URL?) throws {
        print(#function, url)
        var lastComponent = url.lastPathComponent
        let pattern = "(\\.excalidraw)(?=.*\\.excalidraw)"
        if let regex = try? NSRegularExpression(pattern: pattern) {
            let range = NSRange(location: 0, length: lastComponent.utf16.count)
            // 替换掉中间的 ".excalidraw"
            lastComponent = regex.stringByReplacingMatches(in: lastComponent, options: [], range: range, withTemplate: "")
        }
        let newURL = url.deletingLastPathComponent().appendingPathComponent(lastComponent, conformingTo: .fileURL)
        print(newURL)
        try super.write(
            to: newURL,
            options: options,
            originalContentsURL: originalContentsURL
        )
    }
}

#if DEBUG
private struct ExportImagePreviewView: View {
    var body: some View {
        ZStack {
            Text("Hello Export Image View")
        }
        .sheet(isPresented: .constant(true)) {
            if #available(macOS 13.0, *) {
                NavigationStack {
                    ExportImageView(file: .preview)
                        .environmentObject(ExportState())
                }
            }
        }
    }
}


#Preview {
    ExportImagePreviewView()
}
#endif
