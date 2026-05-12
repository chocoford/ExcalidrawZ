//
//  WebView+ScriptMessage.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 2023/7/10.
//

import Foundation
import WebKit
import Logging
#if canImport(PDFKit)
import PDFKit
#endif

protocol AnyExcalidrawZMessage: Codable {
    associatedtype D = Codable
    var event: String { get set }
    var data: D { get set }
}

typealias Collaborator = ExcalidrawCore.CollaboratorsChangedMessage.Collobrator

extension ExcalidrawCore: WKScriptMessageHandler {
    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        do {
            let sanitization = sanitizeScriptMessageBody(message.body)
#if DEBUG
            if !sanitization.nonFiniteNumberPaths.isEmpty {
                logger.warning("[WKScriptMessageHandler] Replaced non-finite numbers in \(scriptMessageEventName(message.body)): \(sanitization.nonFiniteNumberPaths.prefix(12).joined(separator: ", "))")
            }
#endif
            let sanitizedBody = sanitization.value
            let data = try JSONSerialization.data(withJSONObject: sanitizedBody)
            let message = try JSONDecoder().decode(ExcalidrawZMessage.self, from: data)
            
            switch message {
                case .onload:
                    DispatchQueue.main.async {
                        self.isDocumentLoaded = true
                    }
                    logger.info("onload")
                case .stateChanged(let message):
                    onStateChanged(message.data)
                case .blobData(let message):
                    try self.handleBlobData(message.data)
                case .onCopy(let message):
                    try self.handleCopy(message.data)
                case .onFocus:
                    self.webView.shouldHandleInput = false
                case .onBlur:
                    self.webView.shouldHandleInput = true
                case .didSetActiveTool(let message):
                    guard !self.isLoading else { return }
                    if message.data.type == .lasso { return }
                    if message.data.type == .hand {
                        self.lastTool = .hand
                        DispatchQueue.main.async {
                            self.parent?.toolState.setActivedTool(.hand)
                        }
                    } else {
                        self.parent?.toolState.previousActivatedTool = self.parent?.toolState.activatedTool
                        if let tool = ExcalidrawTool(from: message.data.type) {
                            self.lastTool = tool
                            DispatchQueue.main.async {
                                self.parent?.toolState.setActivedTool(tool)
                            }
                        }
                    }
                case .didToggleToolLock(let message):
                    DispatchQueue.main.async {
                        self.parent?.toolState.isToolLocked = message.data
                    }
                case .onLoadLibrary(let message):
                    self.onLoadLibrary(library: message.data)
                case .addToLibrary(let message):
                    self.addToLibrary(item: message.data)
                case .historyStateChanged(let message):
                    switch message.data.type {
                        case .redo:
                            self.canRedo = !message.data.disabled
                        case .undo:
                            self.canUndo = !message.data.disabled
                    }
                case .didPenDown:
                    self.parent?.toolState.inPenMode = true
                    NotificationCenter.default.post(name: .didPencilConnected, object: nil)
                case .didSelectElements(let message):
                    DispatchQueue.main.async {
                        self.updateSelectedElementIDs(message.data.map(\.id))
                    }
                case .didUnselectAllElements:
                    DispatchQueue.main.async {
                        self.clearSelectedElementIDs()
                    }
                case .onElementsChanged:
                    break
                case .onCameraChanged(let message):
                    DispatchQueue.main.async {
                        self.updateCameraState(message.data)
                    }
                case .onAICameraSessionStarted(let message):
                    DispatchQueue.main.async {
                        self.updateAICameraSession(message.data)
                        self.aiCameraEventSink?.aiCameraSessionDidStart(message.data)
                    }
                case .onAICameraSessionUpdated(let message):
                    DispatchQueue.main.async {
                        self.updateAICameraSession(message.data)
                        self.aiCameraEventSink?.aiCameraSessionDidUpdate(message.data)
                    }
                case .onAICameraSessionInterrupted(let message):
                    DispatchQueue.main.async {
                        self.updateAICameraSession(message.data)
                        self.aiCameraEventSink?.aiCameraSessionDidInterrupt(message.data)
                    }
                case .onAICameraSessionSettled(let message):
                    DispatchQueue.main.async {
                        self.updateAICameraSession(message.data)
                        self.aiCameraEventSink?.aiCameraSessionDidSettle(message.data)
                    }
                case .onAICameraSessionEnded(let message):
                    DispatchQueue.main.async {
                        self.updateAICameraSession(message.data)
                        self.aiCameraEventSink?.aiCameraSessionDidEnd(message.data)
                    }
                    
                // Collab
                case .didOpenLiveCollaboration(let message):
                    DispatchQueue.main.async {
                        self.isCollabEnabled = true
                        self.parent?.file?.roomID = message.data.hash.replacingOccurrences(of: "#room=", with: "")
                    }
                case .onCollaboratorsChanged(let message):
                    DispatchQueue.main.async {
                        let collaborators = message.data.compactMap {
                            if case .collaborator(let collaborator) = $0 {
                                return collaborator
                            }
                            return nil
                        }
                        if case .collaborationFile(let currentCollaborationFile) = self.parent?.fileState.currentActiveFile {
                            self.parent?.fileState.collaborators[currentCollaborationFile] = collaborators
                        }
                    }

                case .onDropPDF(let message):
                    self.handleDropPDF(message.data)

                case .openPDFNatively(let message):
                    self.handleOpenPDFNatively(message.data)

                case .onUserSettingsChanged/*(let message)*/:
                    // temp leave alone
                    break
                    // self.handleUserSettingsChanged(message.data)

                case .onCanvasPreferencesChanged(let message):
                    let snapshot = message.data
                    DispatchQueue.main.async {
                        self.parent?.canvasPreferencesState.apply(snapshot)
                    }

                case .log(let logMessage):
                    _ = logMessage
                    // self.onWebLog(message: logMessage)
                    break
            }
        } catch {
            self.logger.error("[WKScriptMessageHandler] Decode received message failed. Raw data:\n\(String(describing: message.body))")
            self.publishError(error)
        }
    }

    private func sanitizeScriptMessageBody(_ value: Any) -> SanitizedScriptMessageBody {
        sanitizeScriptMessageValue(value, path: "$")
    }

    private func scriptMessageEventName(_ value: Any) -> String {
        guard let dictionary = value as? [String: Any],
              let event = dictionary["event"] as? String else {
            return "unknown event"
        }
        return event
    }

    private func sanitizeScriptMessageValue(_ value: Any, path: String) -> SanitizedScriptMessageBody {
        switch value {
            case let dictionary as [String: Any]:
                var paths: [String] = []
                var sanitized: [String: Any] = [:]
                for (key, child) in dictionary {
                    let result = sanitizeScriptMessageValue(child, path: "\(path).\(key)")
                    paths.append(contentsOf: result.nonFiniteNumberPaths)
                    sanitized[key] = result.value
                }
                return SanitizedScriptMessageBody(value: sanitized, nonFiniteNumberPaths: paths)
            case let array as [Any]:
                var paths: [String] = []
                let sanitized = array.enumerated().map { index, child in
                    let result = sanitizeScriptMessageValue(child, path: "\(path)[\(index)]")
                    paths.append(contentsOf: result.nonFiniteNumberPaths)
                    return result.value
                }
                return SanitizedScriptMessageBody(value: sanitized, nonFiniteNumberPaths: paths)
            case let number as NSNumber:
                if CFGetTypeID(number) == CFBooleanGetTypeID() {
                    return SanitizedScriptMessageBody(value: number, nonFiniteNumberPaths: [])
                }
                let double = number.doubleValue
                return double.isFinite
                    ? SanitizedScriptMessageBody(value: number, nonFiniteNumberPaths: [])
                    : SanitizedScriptMessageBody(value: NSNull(), nonFiniteNumberPaths: [path])
            case let double as Double:
                return double.isFinite
                    ? SanitizedScriptMessageBody(value: double, nonFiniteNumberPaths: [])
                    : SanitizedScriptMessageBody(value: NSNull(), nonFiniteNumberPaths: [path])
            case let float as Float:
                return float.isFinite
                    ? SanitizedScriptMessageBody(value: float, nonFiniteNumberPaths: [])
                    : SanitizedScriptMessageBody(value: NSNull(), nonFiniteNumberPaths: [path])
            default:
                return SanitizedScriptMessageBody(value: value, nonFiniteNumberPaths: [])
        }
    }

    private struct SanitizedScriptMessageBody {
        var value: Any
        var nonFiniteNumberPaths: [String]
    }
}

extension ExcalidrawCore {
    func onStateChanged(_ data: StateChangedMessageData) {
        // DIAG: entry point — confirms JS messages reach Swift and whether
        // the early `isLoading` gate or the (later) `loadedFileID == currentFileID`
        // gate is what's dropping updates.
        print("[aiDiag] onStateChanged elements=\(data.data.elements?.count ?? -1) isLoading=\(self.isLoading) parentFileID=\(self.parent?.file?.id ?? "nil")")
        guard !(self.isLoading) else {
            print("[aiDiag] onStateChanged → DROPPED by isLoading gate")
            return
        }
        let type = self.parent?.type
        let currentFileID = self.parent?.file?.id
        let onError = self.publishError
        Task {
            do {
                let loadedID = await self.webActor.loadedFileID
                guard loadedID == currentFileID || type == .collaboration else {
                    print("[aiDiag] onStateChanged → DROPPED by loadedFileID gate. loaded=\(loadedID ?? "nil") current=\(currentFileID ?? "nil")")
                    return
                }

                let elements = data.data.elements
                switch self.parent?.savingType {
                    case .excalidrawPNG, .png:
                        let data = try await self.exportElementsToPNGData(
                            elements: elements ?? [],
                            embedScene: true,
                            colorScheme: .light
                        )
                        await MainActor.run {
                            self.parent?.file?.content = data
                        }
                    case .excalidrawSVG, .svg:
                        let data = try await self.exportElementsToSVGData(
                            elements: elements ?? [],
                            embedScene: true,
                            colorScheme: .light
                        )
                        await MainActor.run {
                            self.parent?.file?.content = data
                        }
                    default:
                        await MainActor.run {
                            do {
                                try self.parent?.file?.update(data: data.data)
                            } catch {
                                onError(error)
                            }
                        }
                }
            } catch {
                onError(error)
            }
        }
    }
    
    func handleBlobData(_ data: Data) throws {
        let json = try JSONSerialization.jsonObject(with: data)
        dump(json)
    }
    
    func handleCopy(_ data: [WebClipboardItem]) throws {
#if canImport(AppKit)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        for item in data {
            let string = item.data
            switch item.type {
                case "text":
                    /*let success = */pasteboard.setString(string, forType: .string)
                case "application/json", "application/vnd.excalidraw+json", "application/vnd.excalidrawlib+json":
                    pasteboard.setString(string, forType: .string)
                case "image/svg+xml":
                    pasteboard.setString(string, forType: .html)
                case "image/png", "image/jpeg", "image/gif", "image/webp", "image/bmp", "image/x-icon", "image/avif", "image/jfif":
                    if let data = Data(
                        base64Encoded: String(string.suffix(
                            string.count - string.distance(
                                from: string.startIndex,
                                to: (string.firstIndex(of: ",") ?? .init(utf16Offset: 0, in: ""))
                            )
                        )),
                        options: [.ignoreUnknownCharacters]
                    ) {
                        let success = pasteboard.setData(data, forType: .png)
                        print(success)
                    } else {
                        pasteboard.setString(string, forType: .png)
                    }
                case "application/octet-stream":
                    pasteboard.setString(string, forType: .fileContents)
                default:
                    break
            }
        }
#elseif canImport(UIKit)
        let pasteboard = UIPasteboard.general
        for item in data {
            let string = item.data
            switch item.type {
                case "text":
                    pasteboard.string = string
                case "application/json", "application/vnd.excalidraw+json", "application/vnd.excalidrawlib+json":
                    pasteboard.string = string
                case "image/svg+xml":
                    pasteboard.setValue(string, forPasteboardType: "public.html")
                case "image/png", "image/jpeg", "image/gif", "image/webp", "image/bmp", "image/x-icon", "image/avif", "image/jfif":
                    if let data = Data(
                        base64Encoded: String(string.suffix(
                            string.count - string.distance(
                                from: string.startIndex,
                                to: (string.firstIndex(of: ",") ?? string.startIndex)
                            )
                        )),
                        options: [.ignoreUnknownCharacters]
                    ) {
                        pasteboard.setData(data, forPasteboardType: "public.png")
                    } else {
                        pasteboard.setValue(string, forPasteboardType: "public.png")
                    }
                case "application/octet-stream":
                    pasteboard.setValue(string, forPasteboardType: "public.data")
                default:
                    break
            }
        }
#endif
    }
    
    func onWebLog(message: LogMessage) {
        let method = message.method
        let message = message.args.map{
            if let arg = $0 {
                let maxLength = 100
                if arg.count > maxLength {
                    return arg.prefix(maxLength - 3) + "..."
                } else {
                    return arg
                }
            } else {
                return "null"
            }
        }.joined(separator: " ")
        switch method {
            case "log":
                self.logger.log(level: .debug, "Receive log from web:\n\(message)")
                break
            case "warn":
                self.logger.warning("Receive warning from web:\n\(message)")
            case "error":
                self.logger.error("Receive warning from error:\n\(message)")
            case "debug":
                self.logger.debug("Receive warning from debug:\n\(message)")
            case "info":
                self.logger.info("Receive info from web:\n\(message)")
                break
            case "trace":
                self.logger.trace("Receive warning from trace:\n\(message)")
            default:
                self.logger.debug("Unhandled log: \(message)")
        }
    }

    func handleDropPDF(_ data: OnDropPDFMessage.OnDropPDFMessageData) {
        // Parse base64 data to PDF data
        guard let pdfData = decodeBase64(data.base64Data) else {
            logger.error("Failed to decode base64 PDF data")
            return
        }
        
#if canImport(PDFKit)
        if PDFDocument(data: pdfData) == nil {
            logger.error("Invalid PDF Data")
            return
        }
#endif

        // Create PDF drop info struct
        let dropInfo = PDFDropInfo(
            pdfData: pdfData,
            fileName: data.fileName,
            sceneX: data.sceneX,
            sceneY: data.sceneY
        )

        // Post notification to trigger PDF insert sheet
        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: .showPDFInsertSheet,
                object: dropInfo
            )
        }

        logger.info("PDF drop event received: \(data.fileName) at (\(data.sceneX), \(data.sceneY))")
    }

    func handleOpenPDFNatively(_ data: OpenPDFNativelyMessage.OpenPDFNativelyMessageData) {
        // Open viewer immediately, then decode PDF in background.
        let placeholderInfo = PDFViewerInfo(
            fileId: data.fileId,
            pdfData: nil,
            mimeType: data.mimeType
        )
        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: .openPDFViewer,
                object: placeholderInfo
            )
        }

        Task.detached(priority: .userInitiated) {
            let start = Date()
            guard let pdfData = decodeBase64FromDataURL(data.dataURL) else {
                self.logger.error("Failed to decode base64 PDF data from dataURL")
                return
            }
            self.logger.info("handleOpenPDFNatively decode PDF time: \(Date().timeIntervalSince(start).formatted())")

#if canImport(PDFKit)
            if PDFDocument(data: pdfData) == nil {
                self.logger.error("Invalid PDF Data")
                return
            }
#endif

            let pdfInfo = PDFViewerInfo(
                fileId: data.fileId,
                pdfData: pdfData,
                mimeType: data.mimeType
            )
            await MainActor.run {
                NotificationCenter.default.post(
                    name: .openPDFViewer,
                    object: pdfInfo
                )
            }
        }

        logger.info("PDF native viewer requested for file: \(data.fileId)")
    }

    func handleUserSettingsChanged(_ settings: UserDrawingSettings) {
        // Save settings to AppPreference on main thread
        DispatchQueue.main.async { [weak self] in
            self?.parent?.appPreference.customDrawingSettings = settings
        }

        logger.info("User drawing settings updated and saved")
    }

    func addToLibrary(item: ExcalidrawLibrary.Item) {
        let context = PersistenceController.shared.container.newBackgroundContext()
        let onError = self.publishError
        Task.detached {
            do {
                try await context.perform {
                    let library = try Library.getPersonalLibrary(context: context)
                    
                    let libraryItem = LibraryItem(context: context)
                    libraryItem.id = item.id
                    libraryItem.status = item.status.rawValue
                    libraryItem.name = item.name
                    libraryItem.createdAt = item.createdAt
                    libraryItem.elements = try JSONEncoder().encode(item.elements)
                    libraryItem.library = library
                    
                    try context.save()
                }
            } catch {
                onError(error)
            }
        }
    }
    
    func onLoadLibrary(library: ExcalidrawLibrary) {
        NotificationCenter.default.post(name: .addLibrary, object: [library])
    }
}

extension ExcalidrawCore {
    enum ExcalidrawZEventType: String, Codable {
        case onload

        case onStateChanged
        case blobData
        case copy
        case onFocus
        case onBlur
        case didSetActiveTool
        case didToggleToolLock
        case onLoadLibrary
        case addToLibrary
        case historyStateChanged
        case didPenDown
        case didSelectElements
        case didUnselectAllElements
        case onElementsChanged
        case onCameraChanged
        case onAICameraSessionStarted
        case onAICameraSessionUpdated
        case onAICameraSessionInterrupted
        case onAICameraSessionSettled
        case onAICameraSessionEnded

        // Collab
        case didOpenLiveCollaboration
        case onCollaboratorsChanged

        // PDF
        case onDropPDF
        case openPDFNatively

        // User Settings
        case onUserSettingsChanged

        // Canvas Preferences
        case onCanvasPreferencesChanged

        case log
    }
    
    enum ExcalidrawZMessage: Codable {
        case onload
        case stateChanged(StateChangedMessage)
        case blobData(BlobDataMessage)
        case onCopy(CopyMessage)
        case onFocus
        case onBlur
        case didSetActiveTool(SetActiveToolMessage)
        case didToggleToolLock(DidtoggleToolLockMessage)
        case onLoadLibrary(OnAddLibraryMessage)
        case addToLibrary(AddToLibraryMessage)
        case historyStateChanged(HistoryStateChangedMessage)
        case didPenDown
        case didSelectElements(DidSelectElementsMessage)
        case didUnselectAllElements
        case onElementsChanged(ElementsChangedMessage)
        case onCameraChanged(CameraChangedMessage)
        case onAICameraSessionStarted(AICameraSessionMessage)
        case onAICameraSessionUpdated(AICameraSessionMessage)
        case onAICameraSessionInterrupted(AICameraSessionMessage)
        case onAICameraSessionSettled(AICameraSessionMessage)
        case onAICameraSessionEnded(AICameraSessionMessage)

        // Collab
        case didOpenLiveCollaboration(DidOpenLiveCollaborationMessage)
        case onCollaboratorsChanged(CollaboratorsChangedMessage)

        // PDF
        case onDropPDF(OnDropPDFMessage)
        case openPDFNatively(OpenPDFNativelyMessage)

        // User Settings
        case onUserSettingsChanged(UserSettingsChangedMessage)

        // Canvas Preferences
        case onCanvasPreferencesChanged(CanvasPreferencesChangedMessage)

        case log(LogMessage)
        
        enum CodingKeys: String, CodingKey {
            case eventType = "event"
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let eventType = try container.decode(ExcalidrawZEventType.self, forKey: .eventType)

            switch eventType {
                case .onload:
                    self = .onload
                case .onStateChanged:
                    self = .stateChanged(try StateChangedMessage(from: decoder))
                case .blobData:
                    self = .blobData(try BlobDataMessage(from: decoder))
                case .copy:
                    self = .onCopy(try CopyMessage(from: decoder))
                case .onFocus:
                    self = .onFocus
                case .onBlur:
                    self = .onBlur
                case .didSetActiveTool:
                    self = .didSetActiveTool(try SetActiveToolMessage(from: decoder))
                case .didToggleToolLock:
                    self = .didToggleToolLock(try DidtoggleToolLockMessage(from: decoder))
                case .onLoadLibrary:
                    self = .onLoadLibrary(try OnAddLibraryMessage(from: decoder))
                case .addToLibrary:
                    self = .addToLibrary(try AddToLibraryMessage(from: decoder))
                case .historyStateChanged:
                    self = .historyStateChanged(try HistoryStateChangedMessage(from: decoder))
                case .didPenDown:
                    self = .didPenDown
                case .didSelectElements:
                    self = .didSelectElements(try DidSelectElementsMessage(from: decoder))
                case .didUnselectAllElements:
                    self = .didUnselectAllElements
                case .onElementsChanged:
                    self = .onElementsChanged(try ElementsChangedMessage(from: decoder))
                case .onCameraChanged:
                    self = .onCameraChanged(try CameraChangedMessage(from: decoder))
                case .onAICameraSessionStarted:
                    self = .onAICameraSessionStarted(try AICameraSessionMessage(from: decoder))
                case .onAICameraSessionUpdated:
                    self = .onAICameraSessionUpdated(try AICameraSessionMessage(from: decoder))
                case .onAICameraSessionInterrupted:
                    self = .onAICameraSessionInterrupted(try AICameraSessionMessage(from: decoder))
                case .onAICameraSessionSettled:
                    self = .onAICameraSessionSettled(try AICameraSessionMessage(from: decoder))
                case .onAICameraSessionEnded:
                    self = .onAICameraSessionEnded(try AICameraSessionMessage(from: decoder))
                    
                // Collab
                case .didOpenLiveCollaboration:
                    self = .didOpenLiveCollaboration(try DidOpenLiveCollaborationMessage(from: decoder))
                case .onCollaboratorsChanged:
                    self = .onCollaboratorsChanged(try CollaboratorsChangedMessage(from: decoder))

                // PDF
                case .onDropPDF:
                    self = .onDropPDF(try OnDropPDFMessage(from: decoder))
                case .openPDFNatively:
                    self = .openPDFNatively(try OpenPDFNativelyMessage(from: decoder))

                // User Settings
                case .onUserSettingsChanged:
                    self = .onUserSettingsChanged(try UserSettingsChangedMessage(from: decoder))

                // Canvas Preferences
                case .onCanvasPreferencesChanged:
                    self = .onCanvasPreferencesChanged(try CanvasPreferencesChangedMessage(from: decoder))

                case .log:
                    self = .log(try LogMessage(from: decoder))
            }
            
        }
        
        func encode(to encoder: Encoder) throws {
            
        }
    }
    
    struct StateChangedMessage: AnyExcalidrawZMessage {
        var event: String
        var data: StateChangedMessageData
    }
    struct CameraChangedMessage: AnyExcalidrawZMessage {
        var event: String
        var data: CameraState
    }
    struct AICameraSessionMessage: AnyExcalidrawZMessage {
        var event: String
        var data: AICameraSessionInfo
    }
    struct StateChangedMessageData: Codable {
        var state: ExcalidrawState?
        var data: ExcalidrawFileData
    }

    struct ExcalidrawState: Codable {
        let showWelcomeScreen: Bool
        let theme, currentChartType, currentItemBackgroundColor, currentItemEndArrowhead: String
        let currentItemFillStyle: String
        let currentItemFontFamily: FontFamily
        let currentItemFontSize, currentItemOpacity, currentItemRoughness: Int
//        let currentItemStartArrowhead: JSONNull?
        let currentItemStrokeColor, currentItemRoundness, currentItemStrokeStyle: String
        let currentItemStrokeWidth: Int
        let currentItemTextAlign, cursorButton: String
//        let editingGroupID: JSONNull?
        let activeTool: ActiveTool
        let penMode, penDetected, exportBackground: Bool
        let exportScale: Int
        let exportEmbedScene, exportWithDarkMode: Bool
//        let gridSize: JSONNull?
        let defaultSidebarDockedPreference: Bool?
        let lastPointerDownWith: String
        let name: String?
//        let openMenu, openSidebar: JSONNull?
        let previousSelectedElementIDS: IDS
        let scrolledOutside: Bool
        let scrollX, scrollY: Double
        let selectedElementIDS, selectedGroupIDS: IDS
        let shouldCacheIgnoreZoom: Bool
        let viewBackgroundColor: String
        let zenModeEnabled: Bool
        let zoom: Zoom
//        let selectedLinearElement: JSONNull?

        enum CodingKeys: String, CodingKey {
            case showWelcomeScreen, theme, currentChartType, currentItemBackgroundColor, currentItemEndArrowhead, currentItemFillStyle, currentItemFontFamily, currentItemFontSize, currentItemOpacity, currentItemRoughness, currentItemStrokeColor, currentItemRoundness, currentItemStrokeStyle, currentItemStrokeWidth, currentItemTextAlign, cursorButton
            
            case activeTool, penMode, penDetected, exportBackground, exportScale, exportEmbedScene, exportWithDarkMode, defaultSidebarDockedPreference, lastPointerDownWith, name
            case previousSelectedElementIDS = "previousSelectedElementIds"
            case scrolledOutside, scrollX, scrollY
            case selectedElementIDS = "selectedElementIds"
            case selectedGroupIDS = "selectedGroupIds"
            case shouldCacheIgnoreZoom, viewBackgroundColor, zenModeEnabled, zoom
            
//            case currentItemStartArrowhead, gridSize, openMenu, openSidebar, selectedLinearElement
//            case editingGroupID = "editingGroupId"
        }
        
        
        // MARK: - ActiveTool
        struct ActiveTool: Codable {
            let type: String
    //        let customType: JSONNull?
            let locked: Bool
    //        let lastActiveTool: JSONNull?
        }

        // MARK: - IDS
        struct IDS: Codable {
        }

        // MARK: - Zoom
        struct Zoom: Codable {
            let value: Double
        }
    }

    struct ExcalidrawFileData: Codable, Hashable {
        // The JSON.stringify of `elements` & `files`
        var dataString: String
        var elements: [ExcalidrawElement]?
        var files: [String : ExcalidrawFile.ResourceFile]
    }

    struct BlobDataMessage: AnyExcalidrawZMessage {
        var event: String
        var data: Data
    }

    struct CopyMessage: AnyExcalidrawZMessage {
        var event: String
        var data: [WebClipboardItem]
    }

    struct WebClipboardItem: Codable {
        var type: String
        var data: String // string or base64
    }

    struct SetActiveToolMessage: AnyExcalidrawZMessage {
        var event: String
        var data: SetActiveToolMessageData
        
        struct SetActiveToolMessageData: Codable {
            var type: Tool
            
            enum Tool: String, Codable {
                case selection
                case rectangle
                case diamond
                case ellipse
                case arrow
                case line
                case freedraw
                case text
                case image
                case eraser
                case laser
                
                case hand
                
                case frame
                case webEmbed = "embeddable"
                case magicFrame = "magicframe"
                case lasso
            }
        }
    }
    
    struct DidtoggleToolLockMessage: AnyExcalidrawZMessage {
        var event: String
        var data: Bool
    }
    
    struct OnAddLibraryMessage: AnyExcalidrawZMessage {
        var event: String
        var data: ExcalidrawLibrary
    }

    struct AddToLibraryMessage: AnyExcalidrawZMessage {
        var event: String
        var data: ExcalidrawLibrary.Item
    }

    struct HistoryStateChangedMessage: AnyExcalidrawZMessage {
        var event: String
        var data: HistoryStateChangedData
     
        struct HistoryStateChangedData: Codable {
            var type: HistoryStateChangeType
            var disabled: Bool
            
            enum HistoryStateChangeType: String, Codable {
                case undo, redo
            }
        }
    }
    
    struct DidSelectElementsMessage: AnyExcalidrawZMessage {
        var event: String
        var data: [ExcalidrawElement]
    }

    struct ElementsChangedMessage: AnyExcalidrawZMessage {
        var event: String
        var data: ElementsChangedMessageData
    }

    struct ElementsChangedMessageData: Codable {
        var count: Int
    }

    struct OnDropPDFMessage: AnyExcalidrawZMessage {
        var event: String
        var data: OnDropPDFMessageData

        struct OnDropPDFMessageData: Codable {
            var fileName: String
            var fileSize: Double
            var base64Data: String
            var sceneX: Double
            var sceneY: Double
        }
    }

    struct OpenPDFNativelyMessage: AnyExcalidrawZMessage {
        var event: String
        var data: OpenPDFNativelyMessageData

        struct OpenPDFNativelyMessageData: Codable {
            var fileId: String
            var dataURL: String
            var mimeType: String
        }
    }

    struct UserSettingsChangedMessage: AnyExcalidrawZMessage {
        var event: String
        var data: UserDrawingSettings
    }

    struct CanvasPreferencesChangedMessage: AnyExcalidrawZMessage {
        var event: String
        var data: CanvasPreferencesSnapshot
    }

    struct DidOpenLiveCollaborationMessage: AnyExcalidrawZMessage {
        var event: String
        var data: DidOpenLiveCollaborationMessageData
        
        struct DidOpenLiveCollaborationMessageData: Codable {
            var hash: String
            var href: String
        }
    }
    
    struct CollaboratorsChangedMessage: AnyExcalidrawZMessage {
        var event: String
        var data: [CollaboratorsChangedMessageData]
        
        enum CollaboratorsChangedMessageData: Codable {
            enum CodingKeys: String, CodingKey {
                case isCurrentUser
            }
            
            case currentUser
            case collaborator(Collobrator)
            case invalid(PartialCollobrator)
            
            init(from decoder: any Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                let isCurrentUser = try container.decode(Bool.self, forKey: .isCurrentUser)
                do {
                    if isCurrentUser {
                        self = .currentUser
                    } else {
                        self = try .collaborator(Collobrator(from: decoder))
                    }
                } catch {
                    self = try .invalid(PartialCollobrator(from: decoder))
                }
            }
            
            func encode(to encoder: any Encoder) throws {
                switch self {
                    case .currentUser:
                        struct CurrentUserPayload: Codable {
                            var isCurrentUser: Bool
                        }
                        try CurrentUserPayload(isCurrentUser: true).encode(to: encoder)
                    case .collaborator(let collobrator):
                        try collobrator.encode(to: encoder)
                    case .invalid(let partialCollaborator):
                        try partialCollaborator.encode(to: encoder)
                }
            }
        }
        
            
        struct Collobrator: Codable, Hashable {
            enum UserState: String, Codable {
                case active, away, idle
            }
            
            enum CodingKeys: String, CodingKey {
                case isCurrentUser
                case socketID = "socketId"
                case userState
                case username
            }
            
            var isCurrentUser: Bool
             var socketID: String
            var userState: UserState
            var username: String
        }
        
        struct PartialCollobrator: Codable {
            enum UserState: String, Codable {
                case active, away, idle
            }
            
            enum CodingKeys: String, CodingKey {
                case isCurrentUser
                case socketID = "socketId"
                case userState
                case username
            }
            
            var isCurrentUser: Bool?
            var socketID: String?
            var userState: UserState?
            var username: String?
        }
    }
    
    // Log
    struct LogMessage: Codable {
        var event: String
        var method: String
        var args: [String?]
    }
}

// MARK: - PDF Drop Info

struct PDFDropInfo: Identifiable, Hashable {
    let id = UUID()
    let pdfData: Data
    let fileName: String
    let sceneX: Double
    let sceneY: Double
}

// MARK: - PDF Viewer Info

struct PDFViewerInfo: Identifiable {
    let id: String  // Use fileId as the identifier
    let fileId: String
    let pdfData: Data?
    let mimeType: String

    init(fileId: String, pdfData: Data?, mimeType: String) {
        self.id = fileId
        self.fileId = fileId
        self.pdfData = pdfData
        self.mimeType = mimeType
    }
}

extension Notification.Name {
    static let showPDFInsertSheet = Notification.Name("showPDFInsertSheet")
}

extension ExcalidrawFile {
    mutating func update(data: ExcalidrawCanvasView.Coordinator.ExcalidrawFileData) throws {
        guard let content = self.content else {
            struct EmptyContentError: LocalizedError {
                var errorDescription: String? { "Invalid excalidraw file." }
            }
            throw EmptyContentError()
        }

        var contentObject = try JSONSerialization.jsonObject(with: content) as! [String : Any]
        guard let dataData = data.dataString.data(using: .utf8),
              let fileDataJson = try JSONSerialization.jsonObject(with: dataData) as? [String : Any] else {
            struct InvalidPayloadError: LocalizedError {
                var errorDescription: String? {
                    "Invalid update payload."
                }
            }
            throw InvalidPayloadError()
        }
        contentObject["elements"] = fileDataJson["elements"]
        contentObject["files"] = fileDataJson["files"]
        contentObject["appState"] = fileDataJson["appState"]
        self.content = try JSONSerialization.data(withJSONObject: contentObject)
        self.elements = data.elements ?? []
        self.files = data.files
    }
}
 
