//
//  ExcalidrawOpenPanel.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 2022/12/31.
//

import Foundation
import AppKit

class ExcalidrawOpenPanel: NSOpenPanel {
    static var importPanel: ExcalidrawOpenPanel {
        let panel = ExcalidrawOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.init(filenameExtension: "excalidraw")].compactMap{ $0 }
        return panel
    }
    
    static var exportPanel: ExcalidrawOpenPanel {
        let panel = ExcalidrawOpenPanel()
        panel.canChooseDirectories = true
        return panel
    }
}

extension ExcalidrawOpenPanel: NSOpenSavePanelDelegate {
    func panel(_ sender: Any, shouldEnable url: URL) -> Bool {
        return url.pathExtension == "excalidraw"
    }
}
