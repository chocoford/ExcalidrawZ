//
//  ExcaliDrawOpenPanel.swift
//  ExcaliDrawZ
//
//  Created by Dove Zachary on 2022/12/31.
//

import Foundation
import AppKit

class ExcaliDrawOpenPanel: NSOpenPanel {
    
    
}

extension ExcaliDrawOpenPanel: NSOpenSavePanelDelegate {
    func panel(_ sender: Any, shouldEnable url: URL) -> Bool {
        return url.pathExtension == "excalidraw"
    }
    
    
}
