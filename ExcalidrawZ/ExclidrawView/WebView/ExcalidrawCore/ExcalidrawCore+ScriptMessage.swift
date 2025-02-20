//
//  WebView+ScriptMessage.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 2023/7/10.
//

import Foundation
import WebKit

protocol AnyExcalidrawZMessage: Codable {
    associatedtype D = Codable
    var event: String { get set }
    var data: D { get set }
}

extension ExcalidrawCore: WKScriptMessageHandler {
    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        do {
            let data = try JSONSerialization.data(withJSONObject: message.body)
            let message = try JSONDecoder().decode(ExcalidrawZMessage.self, from: data)
            
//            self.logger.info("[WKScriptMessageHandler] Did receive message: \(String(describing: message))")
            
            switch message {
                case .onload:
                    DispatchQueue.main.async {
                        self.isDocumentLoaded = true
                    }
                    logger.info("onload")
                case .saveFileDone(let message):
                    onSaveFileDone(message.data)
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
                    if message.data.type == .hand {
                        self.parent?.toolState.inDragMode = true
                    } else {
                        let tool = ExcalidrawTool(from: message.data.type)
                        self.lastTool = tool
                        self.parent?.toolState.activatedTool = tool
                        self.parent?.toolState.inDragMode = false
                    }
                case .getElementsBlob(let blobData):
                    self.flyingBlobsRequest[blobData.data.id]?(blobData.data.blobData)
                case .getElementsSVG(let svgData):
                    self.flyingSVGRequests[svgData.data.id]?(svgData.data.svg)
                case .addLibrary(let message):
                    self.addLibrary(item: message.data)
                case .getAllMedias(let data):
                    self.flyingAllMediasRequests[data.data.id]?(data.data.files)
                case .historyStateChanged(let message):
                    switch message.data.type {
                        case .redo:
                            self.canRedo = !message.data.disabled
                        case .undo:
                            self.canUndo = !message.data.disabled
                    }
                case .didPenDown:
                    self.parent?.toolState.inPenMode = true
                    self.parent?.toolState.inDragMode = false
                case .didSelectElements:
                    DispatchQueue.main.async {
                        if self.parent?.toolState.isBottomBarPresented == true {
                            self.parent?.toolState.isBottomBarPresented = false
                        }
                    }
                case .didUnselectAllElements:
                    DispatchQueue.main.async {
                        if self.parent?.toolState.isBottomBarPresented == false {
                            self.parent?.toolState.isBottomBarPresented = true
                        }
                    }
                case .log(let logMessage):
                    self.onWebLog(message: logMessage)
            }
        } catch {
            self.logger.error("[WKScriptMessageHandler] Decode received message failed. Raw data:\n\(String(describing: message.body))")
            self.publishError(error)
        }
    }
}

extension ExcalidrawCore {
    func onSaveFileDone(_ data: String) {
        print("onSaveFileDone")
    }
    
    func onStateChanged(_ data: StateChangedMessageData) {
        guard !(self.isLoading) else { return }
        let currentFileID = self.parent?.file.id
        let onError = self.publishError
        Task {
            do {
                guard await self.webActor.loadedFileID == currentFileID else {
                    return
                }

                let elements = data.data.elements
                switch self.parent?.savingType {
                    case .excalidrawPNG, .png:
                        let data = try await self.exportElementsToPNGData(elements: elements ?? [], embedScene: true)
                        await MainActor.run {
                            self.parent?.file.content = data
                        }
                    case .excalidrawSVG, .svg:
                        let data = try await self.exportElementsToSVGData(elements: elements ?? [], embedScene: true)
                        await MainActor.run {
                            self.parent?.file.content = data
                        }
                    default:
                        await MainActor.run {
                            do {
                                try self.parent?.file.update(data: data.data)
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
                self.logger.log("Receive log from web:\n\(message)")
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
                self.logger.log("Unhandled log: \(message)")
        }
    }
    
    func addLibrary(item: ExcalidrawLibrary.Item) {
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
    
}

extension ExcalidrawCore {
    enum ExcalidrawZEventType: String, Codable {
        case onload
        
        case onStateChanged
        case saveFileDone
        case blobData
        case copy
        case onFocus
        case onBlur
        case didSetActiveTool
        case getElementsBlob
        case getElementsSVG
        case addLibrary
        case getAllMedias
        case historyStateChanged
        case didPenDown
        case didSelectElements
        case didUnselectAllElements
        
        case log
    }
    
    enum ExcalidrawZMessage: Codable {
        case onload
        case stateChanged(StateChangedMessage)
        case saveFileDone(SaveFileDoneMessage)
        case blobData(BlobDataMessage)
        case onCopy(CopyMessage)
        case onFocus
        case onBlur
        case didSetActiveTool(SetActiveToolMessage)
        case getElementsBlob(ExcalidrawElementsBlobData)
        case getElementsSVG(ExcalidrawElementsSVGData)
        case addLibrary(AddLibraryItemMessage)
        case getAllMedias(GetAllMediasMessage)
        case historyStateChanged(HistoryStateChangedMessage)
        case didPenDown
        case didSelectElements(DidSelectElementsMessage)
        case didUnselectAllElements
        
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
                case .saveFileDone:
                    self = .saveFileDone(try SaveFileDoneMessage(from: decoder))
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
                case .getElementsBlob:
                    self = .getElementsBlob(try ExcalidrawElementsBlobData(from: decoder))
                case .getElementsSVG:
                    self = .getElementsSVG(try ExcalidrawElementsSVGData(from: decoder))
                case .addLibrary:
                    self = .addLibrary(try AddLibraryItemMessage(from: decoder))
                case .getAllMedias:
                    self = .getAllMedias(try GetAllMediasMessage(from: decoder))
                case .historyStateChanged:
                    self = .historyStateChanged(try HistoryStateChangedMessage(from: decoder))
                case .didPenDown:
                    self = .didPenDown
                case .didSelectElements:
                    self = .didSelectElements(try DidSelectElementsMessage(from: decoder))
                case .didUnselectAllElements:
                    self = .didUnselectAllElements
                    
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
    struct StateChangedMessageData: Codable {
        var state: ExcalidrawState?
        var data: ExcalidrawFileData
    }

    struct ExcalidrawState: Codable {
        let showWelcomeScreen: Bool
        let theme, currentChartType, currentItemBackgroundColor, currentItemEndArrowhead: String
        let currentItemFillStyle: String
        let currentItemFontFamily, currentItemFontSize, currentItemOpacity, currentItemRoughness: Int
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
        let lastPointerDownWith, name: String
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

    struct ExcalidrawElementsBlobData: AnyExcalidrawZMessage {
        struct BlobData: Codable {
            var id: String
            var blobData: String
        }
        
        var event: String
        var data: BlobData
    }

    struct ExcalidrawElementsSVGData: AnyExcalidrawZMessage {
        struct SVGData: Codable {
            var id: String
            var svg: String
        }
        
        var event: String
        var data: SVGData
    }

    struct SaveFileDoneMessage: AnyExcalidrawZMessage {
        var event: String
        var data: String //SaveFileDoneMessageData
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
            }
        }
    }

    struct AddLibraryItemMessage: AnyExcalidrawZMessage {
        var event: String
        var data: ExcalidrawLibrary.Item
    }

    struct GetAllMediasMessage: AnyExcalidrawZMessage {
        var event: String
        var data: MediasData
        
        struct MediasData: Codable {
            var id: String
            var files: [ExcalidrawFile.ResourceFile]
        }
        
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
    
    // Log
    struct LogMessage: Codable {
        var event: String
        var method: String
        var args: [String?]
    }
}


extension ExcalidrawFile {
    mutating func update(data: ExcalidrawView.Coordinator.ExcalidrawFileData) throws {
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
                var errorDescription: String? { "Invalid update payload." }
            }
            throw InvalidPayloadError()
        }
        contentObject["elements"] = fileDataJson["elements"]
        contentObject["files"] = fileDataJson["files"]
        
        self.content = try JSONSerialization.data(withJSONObject: contentObject)
        self.elements = data.elements ?? []
        self.files = data.files
    }
}
