//
//  ExcalidrawServer.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 2024/8/9.
//

import Foundation
import FlyingFox
import FlyingSocks

import ChocofordUI

struct ExcalidrawServerLogger: Logging {
    func logDebug(_ debug: @autoclosure () -> String) {
            
    }
    
    func logInfo(_ info: @autoclosure () -> String) {
        
    }
    
    func logWarning(_ warning: @autoclosure () -> String) {
        
    }
    
    func logError(_ error: @autoclosure () -> String) {
        
    }
    
    func logCritical(_ critical: @autoclosure () -> String) {
        
    }
}

class ExcalidrawServer {
    #if DEBUG
    let server = HTTPServer(port: 8486, logger: ExcalidrawServerLogger())
    #else
    let server = HTTPServer(port: 8487, logger: ExcalidrawServerLogger())
    #endif
    init(autoStart: Bool = true) {
        if isPreview { return }
        if autoStart {
            Task {
                try? await self.start()
            }
        }
    }
    
    deinit {
        let server = self.server
        Task {
            await server.stop()
        }
    }
    
    func start() async throws {
        await server.appendRoute(
            "GET /*",
            to: .directory(
                for: .main,
                subPath: "excalidraw-latest",
                serverPath: ""
            )
        )
        try await server.start()
    }
    
    
    func stop() async {
        await server.stop()
    }
}
