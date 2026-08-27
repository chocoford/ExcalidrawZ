//
//  ImportFilesModifier.swift
//  ExcalidrawZ
//

import SwiftUI

struct ImportFilesModifier: ViewModifier {
    @Binding var isPresented: Bool

    func body(content: Content) -> some View {
        content
            .fileImporterWithAlert(
                isPresented: $isPresented,
                allowedContentTypes: [
                    .init(filenameExtension: "excalidraw") ?? .excalidrawFile,
                    .excalidrawPNG,
                    .excalidrawSVG,
                    .png,
                    .svg,
                    .folder
                ],
                allowsMultipleSelection: true
            ) { urls in
                NotificationCenter.default.post(
                    name: .shouldHandleImport,
                    object: urls
                )
            }
    }
}
