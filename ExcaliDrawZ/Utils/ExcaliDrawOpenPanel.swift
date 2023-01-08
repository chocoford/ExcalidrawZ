//
//  ExcalidrawOpenPanel.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 2022/12/31.
//

import Foundation
import AppKit

class ExcalidrawOpenPanel: NSOpenPanel {
    
    
}

extension ExcalidrawOpenPanel: NSOpenSavePanelDelegate {
    func panel(_ sender: Any, shouldEnable url: URL) -> Bool {
        return url.pathExtension == "excalidraw"
    }
    
    
}
