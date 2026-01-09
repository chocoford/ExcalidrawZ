//
//  CircularProgressIndicator.swift
//  ExcalidrawZ
//
//  Created by Claude on 2025/11/29.
//

import SwiftUI

/// Circular progress indicator with arc/sector shape
/// Displays download progress from iCloud for files
struct CircularProgressIndicator: View {
    let progress: Double  // 0.0 to 1.0
    var size: CGFloat = 40
    var lineWidth: CGFloat = 4

    var body: some View {
        ZStack {
            // Background circle
            Circle()
                .fill(.regularMaterial)
                .frame(width: size, height: size)

            // Progress arc
            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    AngularGradient(
                        gradient: Gradient(colors: [.blue, .cyan]),
                        center: .center
                    ),
                    style: StrokeStyle(
                        lineWidth: lineWidth,
                        lineCap: .round
                    )
                )
                .frame(width: size - lineWidth, height: size - lineWidth)
                .rotationEffect(.degrees(-90))

            // Download icon
//            Image(systemSymbol: .arrowDownCircle)
//                .resizable()
//                .scaledToFit()
        }
        .shadow(color: .black.opacity(0.2), radius: 4, x: 0, y: 2)
    }
}

/// File download progress overlay for FileHomeItemView
struct FileDownloadProgressView: View {
    let fileID: String

    @MainActor
    var body: some View {
        let box = FileStatusService.shared.statusBox(fileID: fileID)
        if let progress = box.status.syncStatus?.downloadProgress,
           progress < 1.0 {
            CircularProgressIndicator(progress: progress)
                .transition(.scale.combined(with: .opacity))
        }
    }
}

