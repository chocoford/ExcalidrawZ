//
//  ExcalidrawWebActor.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 2024/10/8.
//

import Foundation
import Logging

actor ExcalidrawWebActor {
    let logger = Logger(label: "ExcalidrawWebActor")
    
    var excalidrawCoordinator: ExcalidrawCore
    
    init(coordinator: ExcalidrawCore) {
        self.excalidrawCoordinator = coordinator
    }
    
    var loadedFileID: String?
    var webView: ExcalidrawWebView { excalidrawCoordinator.webView }
    
    func loadFile(id: String, data: Data, force: Bool = false) async throws {
        let webView = webView
        guard loadedFileID != id || force else { return }
        self.loadedFileID = id
        
        self.logger.info(
            "Load file<\(String(describing: id)), \(data.count.formatted(.byteCount(style: .file)))>, force: \(force), Thread: \(Thread().description)"
        )
        
        var buffer = [UInt8].init(repeating: 0, count: data.count)
        data.copyBytes(to: &buffer, count: data.count)
        let buf = buffer
        await MainActor.run {
            webView.evaluateJavaScript("window.excalidrawZHelper.loadFileBuffer(\(buf), '\(id)'); 0;")
        }
    }
}
