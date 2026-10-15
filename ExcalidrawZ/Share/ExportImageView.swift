//
//  ExportImageView.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 2023/4/3.
//

import SwiftUI
import SwiftyAlert
import ChocofordUI
import UniformTypeIdentifiers
import WebKit

struct ExportImageView: View {
#if canImport(AppKit)
    typealias PlatformImage = NSImage
    private let macOSPreviewSectionHeight: CGFloat = 160
    private let macOSActionsSectionHeight: CGFloat = 36
#elseif canImport(UIKit)
    typealias PlatformImage = UIImage
#endif
    @Environment(\.dismiss) var mordenDismiss
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    @Environment(\.containerHorizontalSizeClass) var containerHorizontalSizeClass
    @Environment(\.alertToast) var alertToast
    
    @EnvironmentObject var exportState: ExportState
    
    var elements: [ExcalidrawElement]
    private let baseFileName: String
    
    private var _dismissAction: (() -> Void)?
    init(
        file: ExcalidrawFile,
        dismissAction: (() -> Void)? = nil
    ) {
        let baseName = (file.name?.isEmpty == false)
        ? (file.name ?? String(localizable: .generalUntitled))
        : String(localizable: .generalUntitled)
        self.elements = file.elements
        self.baseFileName = baseName
        self._fileName = State(initialValue: baseName)
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
    @State private var fileName: String
    @State private var copied: Bool = false
    @State private var hasError: Bool = false
    @State private var latestExportRequestID = UUID()

    @State private var keepEditable = false
    @State private var exportWithBackground = true
    @State private var imageType: Int = 0
    @State private var exportColorScheme: ColorScheme = .light
    @State private var exportScale: Int = 1
    
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
        ShareSubViewContainer(dismiss: dismiss) {
            SwiftUI.Group {
#if os(macOS)
                Center {
                    content
                }
#else
                iOSContent()
#endif
            }
        }
        .watch(value: keepEditable) { newValue in
            exportImageData()
        }
        .watch(value: exportWithBackground) { newValue in
            exportImageData(initial: true)
        }
        .watch(value: imageType) { newValue in
            exportImageData()
        }
        .watch(value: exportScale) { _ in
            exportImageData(initial: true)
        }
        .watch(value: exportColorScheme) { _ in
            exportImageData(initial: true)
        }
        .watch(value: exportType) { _ in
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
    
    @ViewBuilder
    private var content: some View {
        VStack(spacing: 16) {
            previewSection
            fileInfoView

            if let exportedImageData {
                actionsView(exportedImageData.url)
            } else {
                actionsPlaceholderView
            }

            if hasError {
                Text(localizable: .exportImageLoadingError)
                    .foregroundColor(.red)
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
    @ViewBuilder
    private func iOSContent() -> some View {
        NavigationStack {
            Form {
                Section {
                    exportImageSettingItems()
                } header: {
                    VStack {
                        previewSection
                            .frame(height: 200)
                            .padding(.vertical)
                        imageNameField()

                        if hasError && exportedImageData == nil {
                            Text(.localizable(.exportImageLoadingError))
                                .foregroundColor(.red)
                        }
                    }
                } footer: {
                    if let exportedImageData {
                        actionsFooterView(url: exportedImageData.url)
                    } else {
                        actionsFooterPlaceholderView
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

    @ViewBuilder
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

    @ViewBuilder
    private var previewSection: some View {
        ZStack {
#if os(macOS)
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.secondary.opacity(0.08))
                .frame(width: 220, height: 140)
#else
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.secondary.opacity(0.08))
#endif

            if let image, let exportedImageData {
                thumbnailView(image, url: exportedImageData.url)
            } else {
                VStack(spacing: 8) {
                    ProgressView()
                    Text(localizable: .generalLoading)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .overlay {
            if loadingImage, image != nil, exportedImageData != nil {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.regularMaterial.opacity(0.85))

                ProgressView()
            }
        }
#if os(macOS)
        .frame(height: macOSPreviewSectionHeight)
#endif
    }
    
    @ViewBuilder
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
    
    
    @ViewBuilder
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
#if os(iOS)
                        .padding(.bottom, 4)
#endif
                }
                HStack(
                    alignment: .bottom,
                    spacing: {
                        #if os(macOS)
                        -2
                        #else
                        -8
                        #endif
                    }()
                ) {
                    Text(".")
#if os(macOS)
                        .offset(y: -2)
#endif
                        // .padding(.bottom, 4)

                    Picker(selection: $imageType) {
                        Text("png").tag(0)
                        Text("svg").tag(1)
                    } label: {
                    }
                    .pickerStyle(.menu)
                    .buttonStyle(.borderless)
                    .menuIndicator(.visible)
                    .fixedSize()
#if os(macOS)
                    .offset(y: -2)
#endif
                }
            }
        }
    }
    
    @ViewBuilder
    private func exportImageSettingItems() -> some View {
#if os(iOS)
        exportColorSchemeSettingRow
        exportWithBackgroundSettingRow
        exportEditableSettingRow
        exportScaleSettingRow
#else
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                exportColorSchemePicker

                exportWithBackgroundToggle

                exportEditableToggle
            }

            exportScaleSettingRow
        }
#endif
    }

    @ViewBuilder
    private var exportColorSchemeSettingRow: some View {
        HStack {
            Text(localizable: .exportImagePickerColorSchemeLabel)

            Spacer(minLength: 0)

            exportColorSchemePicker
                .labelsHidden()
        }
    }

    @ViewBuilder
    private var exportWithBackgroundSettingRow: some View {
        exportWithBackgroundToggle
    }

    @ViewBuilder
    private var exportEditableSettingRow: some View {
        exportEditableToggle
    }

    @ViewBuilder
    private var exportColorSchemePicker: some View {
        Picker(.localizable(.exportImagePickerColorSchemeLabel), selection: $exportColorScheme) {
            Text(.localizable(.generalColorSchemeLight)).tag(ColorScheme.light)
            Text(.localizable(.generalColorSchemeDark)).tag(ColorScheme.dark)
        }
        .disabled(exportType != .png)
    }

    @ViewBuilder
    private var exportWithBackgroundToggle: some View {
#if os(macOS)
        Toggle(.localizable(.exportImageToggleWithBackground), isOn: $exportWithBackground)
            .toggleStyle(.checkboxStyle)
#elseif os(iOS)
        Toggle(.localizable(.exportImageToggleWithBackground), isOn: $exportWithBackground)
            .toggleStyle(.switch)
#endif
    }

    @ViewBuilder
    private var exportEditableToggle: some View {
#if os(macOS)
        Toggle(.localizable(.exportImageToggleEditable), isOn: $keepEditable)
            .toggleStyle(.checkboxStyle)
#elseif os(iOS)
        Toggle(.localizable(.exportImageToggleEditable), isOn: $keepEditable)
            .toggleStyle(.switch)
#endif
    }

    @ViewBuilder
    private var exportScaleSettingRow: some View {
        HStack {
            Text(localizable: .exportImageScaleTitle)

            Spacer(minLength: 0)

            Picker(
                .localizable(.exportImageScaleTitle),
                selection: $exportScale
            ) {
                Text("1x").tag(1)
                Text("2x").tag(2)
                Text("3x").tag(3)
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .modernButtonStyle(style: .glass, shape: .capsule)
            .frame(maxWidth: containerHorizontalSizeClass == .compact ? 180 : nil)
            .disabled(exportType != .png)
        }
    }
    
    @ViewBuilder
    private func actionsView(_ url: URL) -> some View {
        HStack {
            actionItems(url)
        }
        .modernButtonStyle(size: .regular, shape: .modern)
#if os(macOS)
        .frame(height: macOSActionsSectionHeight)
#endif
    }

    @ViewBuilder
    private var actionsPlaceholderView: some View {
        HStack {
            if #available(macOS 13.0, iOS 16.0, *) {
                Label(.localizable(.exportActionCopy), systemSymbol: .clipboard)
                    .padding(.horizontal, 6)
            } else {
                Label(.localizable(.exportActionCopy), systemSymbol: .docOnClipboard)
                    .padding(.horizontal, 6)
            }

            Label(.localizable(.exportActionSave), systemSymbol: .squareAndArrowDown)
                .padding(.horizontal, 6)
                .padding(.vertical, 1)

            Label(.localizable(.exportActionShare), systemSymbol: .squareAndArrowUp)
                .padding(.horizontal, 6)
                .padding(.vertical, 1)
        }
        .opacity(0.5)
        .modernButtonStyle(size: .regular, shape: .modern)
        .disabled(true)
#if os(macOS)
        .frame(height: macOSActionsSectionHeight)
#endif
    }

    @ViewBuilder
    private func actionsFooterView(url: URL) -> some View {
        if containerHorizontalSizeClass == .compact {
            VStack {
                actionItems(url)
            }
            .modernButtonStyle(style: .glass)
        } else {
            HStack {
                Spacer()
                HStack {
                    actionItems(url)
                }
                .modernButtonStyle(style: .glass)
            }
        }
    }

    @ViewBuilder
    private var actionsFooterPlaceholderView: some View {
        if containerHorizontalSizeClass == .compact {
            VStack {
                actionsPlaceholderItems
            }
            .modernButtonStyle(style: .glass)
        } else {
            HStack {
                Spacer()
                HStack {
                    actionsPlaceholderItems
                }
                .modernButtonStyle(style: .glass)
            }
        }
    }

    @ViewBuilder
    private var actionsPlaceholderItems: some View {
        if #available(macOS 13.0, iOS 16.0, *) {
            Label(.localizable(.exportActionCopy), systemSymbol: .clipboard)
                .padding(.horizontal, 6)
                .frame(maxWidth: containerHorizontalSizeClass == .compact ? .infinity : nil)
        } else {
            Label(.localizable(.exportActionCopy), systemSymbol: .docOnClipboard)
                .padding(.horizontal, 6)
                .frame(maxWidth: containerHorizontalSizeClass == .compact ? .infinity : nil)
        }

        Label(.localizable(.exportActionSave), systemSymbol: .squareAndArrowDown)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .frame(maxWidth: containerHorizontalSizeClass == .compact ? .infinity : nil)

        Label(.localizable(.exportActionShare), systemSymbol: .squareAndArrowUp)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .frame(maxWidth: containerHorizontalSizeClass == .compact ? .infinity : nil)
    }
    
    @ViewBuilder
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
                case .success:
                    break
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
        let exportName = self.fileName.isEmpty ? self.baseFileName : self.fileName
        let requestID = UUID()
        Task.detached {
            do {
                await MainActor.run {
                    latestExportRequestID = requestID
                    loadingImage = true
                    hasError = false
                }

                if initial {
                    let imageData = try await exportState.exportExcalidrawElementsToImage(
                        elements: self.elements,
                        type: .png,
                        name: exportName,
                        embedScene: false,
                        withBackground: self.exportWithBackground,
                        colorScheme: self.exportColorScheme,
                        exportScale: self.exportScale
                    )
                    await MainActor.run {
                        guard latestExportRequestID == requestID else { return }
                        self.image = PlatformImage(data: imageData.data)?
                            .resizeWhileMaintainingAspectRatioToSize(size: .init(width: 200, height: 120))
                        self.exportedImageData = imageData
                        self.fileName = imageData.name
                        self.loadingImage = false
                    }
                } else {
                    let imageData = try await exportState.exportExcalidrawElementsToImage(
                        elements: self.elements,
                        type: self.imageType == 0 ? .png : .svg,
                        name: exportName,
                        embedScene: self.keepEditable,
                        withBackground: self.exportWithBackground,
                        colorScheme: self.exportColorScheme,
                        exportScale: self.exportScale
                    )
                    await MainActor.run {
                        guard latestExportRequestID == requestID else { return }
                        self.exportedImageData = imageData
                        self.loadingImage = false
                    }
                }
            } catch {
                await MainActor.run {
                    guard latestExportRequestID == requestID else { return }
                    self.loadingImage = false
                    self.hasError = self.exportedImageData == nil
                }
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
        let fileWrapper = try FileWrapper(regularFileWithContents: Data(contentsOf: url))
        return fileWrapper
    }
}
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
        var lastComponent = url.lastPathComponent
        let pattern = "(\\.excalidraw)(?=.*\\.excalidraw)"
        if let regex = try? NSRegularExpression(pattern: pattern) {
            let range = NSRange(location: 0, length: lastComponent.utf16.count)
            // 替换掉中间的 ".excalidraw"
            lastComponent = regex.stringByReplacingMatches(in: lastComponent, options: [], range: range, withTemplate: "")
        }
        let newURL = url.deletingLastPathComponent().appendingPathComponent(lastComponent, conformingTo: .fileURL)
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
