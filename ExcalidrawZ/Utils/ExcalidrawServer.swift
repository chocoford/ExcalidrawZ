//
//  ExcalidrawServer.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 2024/8/9.
//

import Foundation
import FlyingFox

import ChocofordUI

class ExcalidrawServer {
    #if DEBUG
    let server = HTTPServer(port: 8486)
    #else
    let server = HTTPServer(port: 8487)
    #endif
    init() {
        if isPreview { return }
        self.start()
    }
    
    deinit {
        self.stop()
    }
    
    func start() {
        Task {
            await server.appendRoute(
                "GET /*",
                to: .directory(
                    for: .main,
                    subPath: "excalidraw-latest",
                    serverPath: ""
                )
            )
            try? await server.start()
        }
    }
    
    
    func stop() {
        Task {
            await server.stop()
        }
    }
}
