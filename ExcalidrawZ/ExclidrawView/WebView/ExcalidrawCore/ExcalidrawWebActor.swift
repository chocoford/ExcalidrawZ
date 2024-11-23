//
//  ExcalidrawWebActor.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 2024/10/8.
//

import Foundation

actor ExcalidrawWebActor {
    var excalidrawCoordinator: ExcalidrawCore
    
    init(coordinator: ExcalidrawCore) {
        self.excalidrawCoordinator = coordinator
    }
    
    var loadedFileID: UUID?
    var webView: ExcalidrawWebView { excalidrawCoordinator.webView }
    
    func loadFile(id: UUID, data: Data, force: Bool = false) async throws {
        let webView = webView
        guard loadedFileID != id || force else { return }
        self.loadedFileID = id
        let startDate = Date()
//        let bufferStart = Date()
        print("Load file<\(String(describing: id)), \(data.count)>, force: \(force), Thread: \(Thread().description)")
        var buffer = [UInt8].init(repeating: 0, count: data.count)
        data.copyBytes(to: &buffer, count: data.count)
        let buf = buffer
//        print("Load buffer done. Time cost: \(Date.now.timeIntervalSince(bufferStart))")
        
//        let dataStringStart = Date()
//        let dataString = data.base64EncodedString() // slower than buffer
//        print("Load data string done. Time cost: \(Date.now.timeIntervalSince(dataStringStart))")

        await MainActor.run {
            webView.evaluateJavaScript("window.excalidrawZHelper.loadFileBuffer(\(buf)); 0;")
        }
        print("load file done. time cost", Date.now.timeIntervalSince(startDate))
    }    
//    func loadFile(id: UUID, data: Data, force: Bool = false) async throws {
//        let webView = webView
//        guard loadedFileID != id || force else { return }
//        self.loadedFileID = id
//        let startDate = Date()
//        
//        let dataString = String(data: data, encoding: .utf8)?
//            .replacingOccurrences(of: "'", with: "\\'")
//            .replacingOccurrences(of: "\\n", with: "\\\\n")
//        
//        guard let dataString else {
//            print("Load file failed.")
//            return
//        }
//        print("[ExcalidrawWebActor loadFile]", dataString)
//        await MainActor.run {
//            webView.evaluateJavaScript("window.excalidrawZHelper.loadFileString('\(dataString)'); 0;")
//        }
//        print("load file done. time cost", Date.now.timeIntervalSince(startDate))
//    }
}
