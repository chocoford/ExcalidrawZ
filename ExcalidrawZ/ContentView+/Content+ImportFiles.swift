//
//  Content+ImportFiles.swift
//  ExcalidrawZ
//
//  Created by Codex on 8/10/25.
//

import SwiftUI
import SwiftyAlert

struct MenuBarImportHandlerModifier: ViewModifier {
    @Environment(\.alert) private var alert
    
    @EnvironmentObject private var fileState: FileState
    
#if canImport(AppKit)
    @State private var window: NSWindow?
#elseif canImport(UIKit)
    @State private var window: UIWindow?
#endif
    
    func body(content: Content) -> some View {
        content
            .bindWindow($window)
            .onReceive(NotificationCenter.default.publisher(for: .shouldHandleImport)) { notification in
                handleImport(notification)
            }
    }
    
    private func handleImport(_ notification: Notification) {
        guard let urls = notification.object as? [URL] else { return }
        guard window?.isKeyWindow == true else { return }
        
        Task.detached {
            do {
                try await fileState.importFiles(urls)
            } catch {
                await MainActor.run {
                    alert(error: error)
                }
            }
        }
    }
}
