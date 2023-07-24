//
//  WebView+Download.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 2023/7/10.
//

import Foundation
import WebKit
import ComposableArchitecture

extension ExcalidrawWebView.Coordinator: WKDownloadDelegate {
    func download(_ download: WKDownload, decideDestinationUsing response: URLResponse, suggestedFilename: String) async -> URL? {
        let fileManager: FileManager = FileManager.default
        let directory: URL
        do {
            if #available(macOS 13.0, *) {
                directory = try fileManager.url(for: .itemReplacementDirectory, in: .userDomainMask, appropriateFor: .applicationSupportDirectory, create: true)
            } else if let temp = URL(string: NSTemporaryDirectory()) {
                directory = temp
                try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            } else {
                return nil
            }
            
            let fileExtension = suggestedFilename.components(separatedBy: ".").last ?? "png"
            
//            self.parent.store.withState{$0}.currentFile
            
            let fileName = self.parent.store.withState{$0}.currentFile?.name?.appending(".\(fileExtension)") ?? suggestedFilename
            
            let url = directory.appendingPathComponent(fileName, conformingTo: .image)
            if fileManager.fileExists(atPath: url.absoluteString) {
                try fileManager.removeItem(at: url)
            }
            
            if let request = download.originalRequest {
                self.downloads[request] = url;
            }
            print(url.isFileURL) // false
            self.parent.store.send(
                .delegate(
                    .onBeginExport(
                        .init(
                            url: url, download: download
                        )
                    )
                )
            )

            return url;
        } catch {
            logger.error("\(error)")
            return nil
        }
    }

    @MainActor
    func downloadDidFinish(_ download: WKDownload) {
        guard let request = download.originalRequest,
              let url = downloads[request] else { return }
        logger.info("download did finished: \(url)")
        self.parent.store.send(.delegate(.onExportDone))
//        if self.parent.store.state.exportingState != nil {
//            self.parent.store.send(.setExportingState(.init(url: url, download: download, done: true)))
//        }
        downloads.removeValue(forKey: request)
    }
}
