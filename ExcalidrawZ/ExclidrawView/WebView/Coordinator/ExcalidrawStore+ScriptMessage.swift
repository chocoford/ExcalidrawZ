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

extension ExcalidrawView.Coordinator: WKScriptMessageHandler {
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
                    // prevent color schmee change flash
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { self.parent.isLoading = false }
                    logger.info("onload")
                case .saveFileDone(let message):
                    onSaveFileDone(message.data)
                case .stateChanged(let message):
                    try onStateChanged(message.data)
                case .blobData(let message):
                    try self.handleBlobData(message.data)
                case .onCopy(let message):
                    try self.handleCopy(message.data)
                case .onFocus:
                    self.webView.shouldHandleInput = false
                case .onBlur:
                    self.webView.shouldHandleInput = true
                case .didSetActiveTool(let message):
                    let tool = ExcalidrawTool(from: message.data.type)
                    self.lastTool = tool
                    self.parent.toolState.activatedTool = tool
                case .getElementsBlob(let blobData):
                    self.flyingBlobsRequest[blobData.data.id]?(blobData.data.blobData)
                case .getElementsSVG(let svgData):
                    self.flyingSVGRequests[svgData.data.id]?(svgData.data.svg)
                    
                case .log(let logMessage):
                    self.onWebLog(message: logMessage)
            }
        } catch {
            self.logger.error("[WKScriptMessageHandler] Decode received message failed. Raw data:\n\(String(describing: message.body))")
            self.parent.onError(error)
        }
    }
}

extension ExcalidrawView.Coordinator {
    func onSaveFileDone(_ data: String) {
        print("onSaveFileDone")
    }
    
    func onStateChanged(_ data: StateChangedMessageData) throws {
        guard !self.parent.isLoading else { return }
        guard let data = data.data.dataString.data(using: .utf8) else {
            throw AppError.fileError(.createError)
        }
        self.parent.fileState.updateCurrentFileData(data: data)
    }
    
    func handleBlobData(_ data: Data) throws {
        let json = try JSONSerialization.jsonObject(with: data)
        dump(json)
    }
    
    func handleCopy(_ data: [WebClipboardItem]) throws {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        for item in data {
            let string = item.data
            switch item.type {
                case "text":
                    let success = pasteboard.setString(string, forType: .string)
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
        
    }
    
    
    func onWebLog(message: LogMessage) {
        let method = message.method
        let message = message.args.joined(separator: " ")
        switch method {
            case "log":
//                self.logger.log("\(message)")
                break
            case "warn":
                self.logger.warning("\(message)")
            case "error":
                self.logger.error("\(message)")
            case "debug":
                self.logger.debug("\(message)")
            case "info":
//                self.logger.info("\(message)")
                break
            case "trace":
                self.logger.trace("\(message)")
            default:
                self.logger.log("Unhandled log: \(message)")
        }
    }
}


extension ExcalidrawView.Coordinator {
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
        var dataString: String
        var elements: [ExcalidrawElement]?
        var files: [LoadedFile]?
        
        // MARK: - LoadedFile
        struct LoadedFile: Codable, Hashable {
            let mimeType, id, dataURL: String
            let created, lastRetrieved: Int
        }
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
            }
        }
    }
    
    
    // Log
    struct LogMessage: Codable {
        var event: String
        var method: String
        var args: [String]
    }
}
