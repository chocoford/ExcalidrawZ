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

extension ExcalidrawWebView.Coordinator: WKScriptMessageHandler {
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        do {
            let data = try JSONSerialization.data(withJSONObject: message.body)
            let message = try JSONDecoder().decode(ExcalidrawZMessage.self, from: data)
            
            switch message {
                case .saveFileDone(let message):
                    onSaveFileDone(message.data)
                case .stateChanged(let message):
                    try onStateChanged(message.data)
            }
        } catch {
            logger.error("\(error)")
        }
    }
}

extension ExcalidrawWebView.Coordinator {
    func onSaveFileDone(_ data: String) {
        
    }
    
    func onStateChanged(_ data: StateChangedMessageData) throws {
        guard let fileData = data.data.data(using: .utf8) else { throw AppError.fileError(.createError) }
//        if let file = self.parent.currentFile {
//            // parse current file content
//            try file.updateElements(with: fileData)
//        } else {
//            // create the file
//            DispatchQueue.main.async {
////                self.parent.store.send(.newFile(resData))
//            }
//        }
    }
}


extension ExcalidrawWebView.Coordinator {
    enum ExcalidrawZEventType: String, Codable {
        case onStateChanged
        case saveFileDone
    }
    
    enum ExcalidrawZMessage: Codable {
        case stateChanged(StateChangedMessage)
        case saveFileDone(SaveFileDoneMessage)
        
        enum CodingKeys: String, CodingKey {
            case eventType = "event"
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let eventType = try container.decode(ExcalidrawZEventType.self, forKey: .eventType)
            
            switch eventType {
                case .onStateChanged:
                    self = .stateChanged(try StateChangedMessage(from: decoder))
                case .saveFileDone:
                    self = .saveFileDone(try SaveFileDoneMessage(from: decoder))
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
        var state: ExcalidrawState
        var data: String
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
        let defaultSidebarDockedPreference: Bool
        let lastPointerDownWith, name: String
//        let openMenu, openSidebar: JSONNull?
        let previousSelectedElementIDS: IDS
        let scrolledOutside: Bool
        let scrollX, scrollY: Int
        let selectedElementIDS, selectedGroupIDS: IDS
        let shouldCacheIgnoreZoom, showStats: Bool
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
            case shouldCacheIgnoreZoom, showStats, viewBackgroundColor, zenModeEnabled, zoom
            
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
            let value: Int
        }
    }


    struct SaveFileDoneMessage: AnyExcalidrawZMessage {
        var event: String
        var data: String //SaveFileDoneMessageData
    }
}
