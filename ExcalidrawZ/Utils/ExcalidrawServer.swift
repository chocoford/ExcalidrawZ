//
//  ExcalidrawServer.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 2024/8/9.
//

import Foundation
//import Swifter
import FlyingFox

//class ExcalidrawServer {
//    let server = HttpServer()
//    
//    let url = Bundle.main.url(forResource: "index", withExtension: "html", subdirectory: "excalidraw")!
//    var dir: URL {
//        url.deletingLastPathComponent()
//    }
//    init() {
//        self.start()
//    }
//    
//    func start(port: in_port_t = 8487) {
//        print("shareFilesFromDirectory: \(dir.path(percentEncoded: false))")
//        server["/"] = scopes {
//          html {
//            body {
//              center {
//                img { src = "https://swift.org/assets/images/swift.svg" }
//              }
//            }
//          }
//        }
//        server["/:path"] = shareFilesFromDirectory(dir.path(percentEncoded: false))
//        do {
//            try server.start(in_port_t(port))
//            print("Server has started ( port = \(port) ). Try to connect now...")
//        } catch {
//            print("Server start error: \(error)")
//        }
//    }
//
//    func stop() {
//        server.stop()
//    }
//}


class ExcalidrawServer {
    
    let url = Bundle.main.url(forResource: "index", withExtension: "html", subdirectory: "excalidraw-latest")!
    var dir: URL {
        url.deletingLastPathComponent()
    }
    
    init() {
        self.start()
    }
    
    func start() {
        let server = HTTPServer(port: 8487)
        Task {
            await server.appendRoute(
                "GET /*",
                to: .directory(
                    for: .main,
                    subPath: "excalidraw",
                    serverPath: ""
                )
            )
            try? await server.start()
        }
    }
}
