//
//  WebView+Download.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 2023/7/10.
//

import Foundation
import WebKit


extension ExcalidrawWebView.Coordinator: WKDownloadDelegate {
    func download(_ download: WKDownload, decideDestinationUsing response: URLResponse, suggestedFilename: String) async -> URL? {
        switch suggestedFilename.components(separatedBy: ".").last {
            case .some("excalidraw"):
//                return onDownloadExcalidrawFile(download, decideDestinationUsing: response, suggestedFilename: suggestedFilename)
                return nil
                
            case .some("png"):
                return onExportPNG(download, decideDestinationUsing: response, suggestedFilename: suggestedFilename)
                
            default:
                return nil
        }
    }

    @MainActor
    func downloadDidFinish(_ download: WKDownload) {
        guard let request = download.originalRequest,
              let url = downloads[request] else { return }
        logger.info("download did finished: \(url)")
//        self.parent.store.send(.delegate(.onExportDone))
//        if self.parent.store.state.exportingState != nil {
//            self.parent.store.send(.setExportingState(.init(url: url, download: download, done: true)))
//        }
        downloads.removeValue(forKey: request)
    }
    
    func onDownloadExcalidrawFile(_ download: WKDownload, decideDestinationUsing response: URLResponse, suggestedFilename: String) -> URL? {
        let fileManager: FileManager = FileManager.default

        do {
            guard var directory: URL = try getTempDirectory() else { return nil }
            directory = directory.appendingPathComponent("file_downloads", conformingTo: .directory)
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            
            
        } catch {
//            self.parent.store.send(.setError(.init(error)))
        }
        return nil
    }
    
    
    func onExportPNG(_ download: WKDownload, decideDestinationUsing response: URLResponse, suggestedFilename: String) -> URL? {
        let fileManager: FileManager = FileManager.default
        do {
            guard let directory: URL = try getTempDirectory() else { return nil }
            let fileExtension = suggestedFilename.components(separatedBy: ".").last ?? "png"
            let fileName = "" // self.parent.store.withState{$0}.currentFile?.name?.appending(".\(fileExtension)") ?? suggestedFilename
            let url = directory.appendingPathComponent(fileName, conformingTo: .image)
            if fileManager.fileExists(atPath: url.absoluteString) {
                try fileManager.removeItem(at: url)
            }
            
            if let request = download.originalRequest {
                self.downloads[request] = url;
            }
            
//            self.parent.store.send(
//                .delegate(
//                    .onBeginExport(
//                        .init(
//                            url: url, download: download
//                        )
//                    )
//                )
//            )
            
            return url;
        } catch {
//            self.parent.store.send(.setError(.init(error)))
            return nil
        }
    }
}
