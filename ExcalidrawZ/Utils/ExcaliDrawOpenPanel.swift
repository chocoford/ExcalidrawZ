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
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.allowedContentTypes = [.init(filenameExtension: "excalidraw") ?? .excalidrawFile]
        panel.prompt = "import"
        return panel
    }
    
    static var exportPanel: ExcalidrawOpenPanel {
        let panel = ExcalidrawOpenPanel()
        panel.canChooseDirectories = true
        panel.prompt = "export"
        return panel
    }
}

extension ExcalidrawOpenPanel: NSOpenSavePanelDelegate {
    func panel(_ sender: Any, shouldEnable url: URL) -> Bool {
        return url.pathExtension == "excalidraw"
    }
}
