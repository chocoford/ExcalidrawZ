//
//  Content+PrintModifier.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 4/1/25.
//

import SwiftUI

struct PrintModifier: ViewModifier {
    @Environment(\.alertToast) var alertToast

    @EnvironmentObject var exportState: ExportState

#if canImport(AppKit)
    @State private var window: NSWindow?
#elseif canImport(UIKit)
    @State private var window: UIWindow?
#endif
    
    @State private var isPreparingForPrint = false
    
    func body(content: Content) -> some View {
        content
            .sheet(isPresented: .constant(isPreparingForPrint)) {
                ProgressView {
                    Text(.localizable(.generalLoading))
                }
                .padding(.horizontal, 40)
            }
            .bindWindow($window)
#if os(macOS)
            .onReceive(NotificationCenter.default.publisher(for: .togglePrintModalSheet)) { _ in
                if window?.isKeyWindow == true {
                    isPreparingForPrint = true
                    Task.detached(priority: .background) {
                        do {
                            let imageData = try await exportState.exportCurrentFileToImage(
                                type: .png,
                                embedScene: false,
                                withBackground: true
                            ).data
                            await MainActor.run {
                                if let image = NSImage(dataIgnoringOrientation: imageData) {
                                    exportPDF(image: image)
                                }
                            }
                        } catch {
                            await alertToast(error)
                        }
                        await MainActor.run {
                            isPreparingForPrint = false
                        }
                    }
                }
            }
#endif
    }
}
