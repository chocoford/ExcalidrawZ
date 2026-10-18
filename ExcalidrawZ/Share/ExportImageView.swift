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
    private let macOSContentWidth: CGFloat = 340
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
    
    private let allContent: ExportImageContent
    private let selectedContent: ExportImageContent
    private let exportCoordinator: ExcalidrawCore?
    private let baseFileName: String
    
    private var _dismissAction: (() -> Void)?
    init(
        file: ExcalidrawFile,
        context: ImageExportContext = .init(),
        dismissAction: (() -> Void)? = nil
    ) {
        let baseName = (file.name?.isEmpty == false)
        ? (file.name ?? String(localizable: .generalUntitled))
        : String(localizable: .generalUntitled)
        self.allContent = ExportImageContent(file: file)
        self.selectedContent = ExportImageContent(file: file, selectedElementIDs: context.selectedElementIDs)
        self.exportCoordinator = context.coordinator
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
    @State private var loadingImage = true
    @State private var showFileExporter = false
    @State private var showShare: Bool = false
    @State private var fileName: String
    @State private var copied: Bool = false
    @State private var hasError: Bool = false
    @State private var latestExportRequestID = UUID()
    @State private var renderedOptions: RenderOptions?

    @State private var exportScope: ExportImageScope = .all
    @State private var keepEditable = false
    @State private var exportWithBackground = true
    @State private var imageType: Int = 0
    @State private var exportColorScheme: ColorScheme = .light
    @State private var exportScale: Int = 1

    private struct RenderOptions: Hashable {
        let scope: ExportImageScope
        let imageType: Int
        let keepEditable: Bool
        let withBackground: Bool
        let colorScheme: ColorScheme
        let scale: Int
    }

    private var renderOptions: RenderOptions {
        RenderOptions(
            scope: exportScope,
            imageType: imageType,
            keepEditable: keepEditable,
            withBackground: exportWithBackground,
            colorScheme: imageType == 0 ? exportColorScheme : .light,
            scale: imageType == 0 ? exportScale : 1
        )
    }

    private var isExportReady: Bool {
        exportedImageData != nil && renderedOptions == renderOptions && !loadingImage
    }
    
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
            if #available(macOS 26.0, iOS 26.0, *) {
                GlassEffectContainer(spacing: 4) {
                    platformContent
                }
            } else {
                platformContent
            }
        }
        .task(id: renderOptions) {
            await exportImageData(options: renderOptions)
        }
        .onDisappear {
            latestExportRequestID = UUID()
            exportedImageData?.removeTemporaryFile()
            exportedImageData = nil
            renderedOptions = nil
            loadingImage = true
            exportState.status = .notRequested
        }
    }

    @ViewBuilder
    private var platformContent: some View {
#if os(macOS)
        Center {
            content
        }
#else
        iOSContent()
#endif
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
#if os(macOS)
        .frame(width: macOSContentWidth)
#endif
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
        .allowsHitTesting(isExportReady)
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
        VStack(spacing: 12) {
            imageNameField()
            
            exportImageSettingItems()
                .controlSize(horizontalSizeClass == .compact ? .mini : .regular)
        }
        .font(horizontalSizeClass == .compact ? .footnote : .body)
        .animation(.default, value: keepEditable)
    }
    
    
    @ViewBuilder
    private func imageNameField() -> some View {
        HStack(alignment: .center, spacing: 8) {
            fileNameTextField

            if keepEditable {
                Text(".excalidraw")
                    .lineLimit(1)
                    .fixedSize()
            }

            Picker(selection: $imageType) {
                Text(".png").tag(0)
                Text(".svg").tag(1)
            } label: {
                EmptyView()
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .menuIndicator(.visible)
            .modernButtonStyle(style: .glass, size: .regular, shape: .capsule)
            .fixedSize()
        }
    }

    @ViewBuilder
    private var fileNameTextField: some View {
        if #available(macOS 26.0, iOS 26.0, *) {
            TextField("", text: $fileName)
                .textFieldStyle(.plain)
                .padding(.horizontal, 12)
                .frame(height: 30)
                .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 10))
        } else {
            TextField("", text: $fileName)
                .textFieldStyle(.roundedBorder)
                .frame(height: 30)
        }
    }
    
    @ViewBuilder
    private func exportImageSettingItems() -> some View {
#if os(iOS)
        exportScopeSettingRow
        exportColorSchemeSettingRow
        exportWithBackgroundSettingRow
        exportEditableSettingRow
        exportScaleSettingRow
#else
        if #available(macOS 26.0, *) {
            macOSSettingsGrid
                .buttonSizing(.flexible)
        } else {
            macOSSettingsGrid
        }
#endif
    }

#if os(macOS)
    private var macOSSettingsGrid: some View {
        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
            GridRow {
                Text(localizable: .exportImageScopeLabel)
                    .frame(maxWidth: .infinity, alignment: .leading)
                exportScopePicker
                    .gridColumnAlignment(.trailing)
            }
            GridRow {
                Text(localizable: .exportImagePickerColorSchemeLabel)
                exportColorSchemePicker
                    .labelsHidden()
            }
            GridRow {
                Text(localizable: .exportImageToggleWithBackground)
                exportWithBackgroundToggle
                    .labelsHidden()
            }
            GridRow {
                Text(localizable: .exportImageToggleEditable)
                exportEditableToggle
                    .labelsHidden()
            }
            GridRow {
                Text(localizable: .exportImageScaleTitle)
                exportScalePicker
            }
        }
    }
#endif

    @ViewBuilder
    private var exportScopeSettingRow: some View {
        HStack {
            Text(localizable: .exportImageScopeLabel)
            Spacer(minLength: 0)
            exportScopePicker
        }
    }

    private var exportScopePicker: some View {
        Picker(.localizable(.exportImageScopeLabel), selection: $exportScope) {
            Text(.localizable(.exportImageScopeAll)).tag(ExportImageScope.all)
            Text(.localizable(.exportImageScopeSelected)).tag(ExportImageScope.selected)
        }
        .labelsHidden()
        .pickerStyle(.segmented)
        .modernButtonStyle(style: .glass, size: .regular, shape: .capsule)
        .disabled(selectedContent.elements.isEmpty)
        .frame(width: 180, alignment: .leading)
    }

    @ViewBuilder
    private var exportColorSchemeSettingRow: some View {
        HStack {
            Text(localizable: .exportImagePickerColorSchemeLabel)

            Spacer(minLength: 0)

            exportColorSchemePicker
                .labelsHidden()
                .fixedSize()
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
#if os(macOS)
        .pickerStyle(.segmented)
        .frame(width: 180)
#else
        .pickerStyle(.menu)
#endif
        .modernButtonStyle(style: .glass, size: .regular, shape: .capsule)
        .disabled(imageType != 0)
    }

    @ViewBuilder
    private var exportWithBackgroundToggle: some View {
#if os(macOS)
        Toggle(.localizable(.exportImageToggleWithBackground), isOn: $exportWithBackground)
            .toggleStyle(.switch)
            .controlSize(.small)
#elseif os(iOS)
        Toggle(.localizable(.exportImageToggleWithBackground), isOn: $exportWithBackground)
            .toggleStyle(.switch)
#endif
    }

    @ViewBuilder
    private var exportEditableToggle: some View {
#if os(macOS)
        Toggle(.localizable(.exportImageToggleEditable), isOn: $keepEditable)
            .toggleStyle(.switch)
            .controlSize(.small)
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

            exportScalePicker
        }
    }

    private var exportScalePicker: some View {
        Picker(.localizable(.exportImageScaleTitle), selection: $exportScale) {
            Text("1x").tag(1)
            Text("2x").tag(2)
            Text("3x").tag(3)
        }
        .labelsHidden()
        .pickerStyle(.segmented)
        .modernButtonStyle(style: .glass, size: .regular, shape: .capsule)
        .frame(width: 180, alignment: .leading)
        .disabled(imageType != 0)
    }
    
    @ViewBuilder
    private func actionsView(_ url: URL) -> some View {
        HStack {
            actionItems(url)
        }
        .modernButtonStyle(style: .glass, size: .regular, shape: .capsule)
        .disabled(!isExportReady)
#if os(macOS)
        .frame(height: macOSActionsSectionHeight)
#endif
    }

    private var actionItemMaxWidth: CGFloat? {
#if os(macOS)
        .infinity
#else
        containerHorizontalSizeClass == .compact ? .infinity : nil
#endif
    }

    @ViewBuilder
    private var actionsPlaceholderView: some View {
        HStack {
            if #available(macOS 13.0, iOS 16.0, *) {
                Label(.localizable(.exportActionCopy), systemSymbol: .clipboard)
                    .padding(.horizontal, 6)
                    .frame(maxWidth: actionItemMaxWidth)
            } else {
                Label(.localizable(.exportActionCopy), systemSymbol: .docOnClipboard)
                    .padding(.horizontal, 6)
                    .frame(maxWidth: actionItemMaxWidth)
            }

            Label(.localizable(.exportActionSave), systemSymbol: .squareAndArrowDown)
                .padding(.horizontal, 6)
                .padding(.vertical, 1)
                .frame(maxWidth: actionItemMaxWidth)

            Label(.localizable(.exportActionShare), systemSymbol: .squareAndArrowUp)
                .padding(.horizontal, 6)
                .padding(.vertical, 1)
                .frame(maxWidth: actionItemMaxWidth)
        }
        .opacity(0.5)
        .modernButtonStyle(style: .glass, size: .regular, shape: .capsule)
        .disabled(true)
#if os(macOS)
        .frame(height: macOSActionsSectionHeight)
#endif
    }

    @ViewBuilder
    private func actionsFooterView(url: URL) -> some View {
        SwiftUI.Group {
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
        .disabled(!isExportReady)
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
                .frame(maxWidth: actionItemMaxWidth)
        } else {
            Label(.localizable(.exportActionCopy), systemSymbol: .docOnClipboard)
                .padding(.horizontal, 6)
                .frame(maxWidth: actionItemMaxWidth)
        }

        Label(.localizable(.exportActionSave), systemSymbol: .squareAndArrowDown)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .frame(maxWidth: actionItemMaxWidth)

        Label(.localizable(.exportActionShare), systemSymbol: .squareAndArrowUp)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .frame(maxWidth: actionItemMaxWidth)
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
            .frame(maxWidth: actionItemMaxWidth)
        }
        .disabled(copied)
        
        Button {
            showFileExporter = true
        } label: {
            Label(.localizable(.exportActionSave), systemSymbol: .squareAndArrowDown)
                .padding(.horizontal, 6)
                .padding(.vertical, 1)
                .frame(maxWidth: actionItemMaxWidth)
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
                    .frame(maxWidth: actionItemMaxWidth)
            }
        } else {
            Button {
                self.showShare = true
            } label: {
                Label(.localizable(.exportActionShare), systemSymbol: .squareAndArrowUp)
                    .padding(.horizontal, 6)
                    .frame(maxWidth: actionItemMaxWidth)
            }
            .background(
                SharingsPicker(
                    isPresented: $showShare,
                    sharingItems: [url]
                )
            )
        }
    }
    
    @MainActor
    private func exportImageData(options: RenderOptions) async {
        guard !Task.isCancelled else { return }
        if isPreview {
            image = .init(named: "Layout-Inspector-Floating")
            exportedImageData = .init(name: "Preview", data: Data(), url: URL(string: "https://www.google.com")!)
            renderedOptions = options
            loadingImage = false
            return
        }

        let content = options.scope == .all ? allContent : selectedContent
        let exportName = fileName.isEmpty ? baseFileName : fileName
        let requestID = UUID()
        latestExportRequestID = requestID
        loadingImage = true
        hasError = false
        copied = false

        var pendingExport: ExportedImageData?
        var previewExport: ExportedImageData?
        defer {
            pendingExport?.removeTemporaryFile()
            previewExport?.removeTemporaryFile()
        }

        do {
            let output = try await exportState.exportExcalidrawElementsToImage(
                elements: content.elements,
                files: content.files,
                coordinator: exportCoordinator,
                type: options.imageType == 0 ? .png : .svg,
                name: exportName,
                embedScene: options.keepEditable,
                withBackground: options.withBackground,
                colorScheme: options.colorScheme,
                exportScale: options.scale
            )
            pendingExport = output
            try Task.checkCancellation()

            // SVG remains the downloadable output; a separate PNG is used only for its preview.
            let previewData: Data
            if options.imageType == 0 {
                previewData = output.data
            } else {
                let preview = try await exportState.exportExcalidrawElementsToImage(
                    elements: content.elements,
                    files: content.files,
                    coordinator: exportCoordinator,
                    type: .png,
                    name: exportName,
                    embedScene: false,
                    withBackground: options.withBackground,
                    colorScheme: options.colorScheme
                )
                previewExport = preview
                previewData = preview.data
            }
            try Task.checkCancellation()
            guard latestExportRequestID == requestID else { return }

            guard let previewImage = PlatformImage(data: previewData)?
                .resizeWhileMaintainingAspectRatioToSize(size: .init(width: 200, height: 120)) else {
                throw CocoaError(.coderReadCorrupt)
            }
            image = previewImage
            exportedImageData?.removeTemporaryFile()
            exportedImageData = output
            pendingExport = nil
            renderedOptions = options
            loadingImage = false
        } catch {
            guard !Task.isCancelled, latestExportRequestID == requestID else { return }
            exportedImageData?.removeTemporaryFile()
            exportedImageData = nil
            image = nil
            loadingImage = false
            hasError = true
            alertToast(error)
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
