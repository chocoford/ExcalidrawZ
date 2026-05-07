//
//  MessageImageView.swift
//  ExcalidrawZ
//
//  Created by Chocoford on 5/4/26.
//

import SwiftUI
import LLMCore
import ChocofordEssentials

/// Inline thumbnail for an attachment on a chat message — used both by user
/// bubbles and tool-result cards (e.g. canvas screenshot tool). Decodes off
/// the main thread to keep scroll smooth.
struct MessageImageView: View {
    var file: ChatMessageContent.File

    @State private var image: Image?

    var body: some View {
        ZStack {
            if let image {
                image
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: 200, maxHeight: 200)
                    .cornerRadius(8)
            }
        }
        .onAppear {
            loadImage()
        }
    }

    private func loadImage() {
        Task.detached {
            var image: Image? = nil
            if case .base64EncodedImage(let base64) = file {
                if let base64ContentString = base64.components(separatedBy: ",").last,
                   let data = Data(base64Encoded: base64ContentString),
                   let uiImage = PlatformImage(data: data) {
                    image = Image(platformImage: uiImage)
                }
            } else if case .image(let url) = file {
                if let data = try? Data(contentsOf: url),
                   let nsImage = PlatformImage(data: data) {
                    image = Image(platformImage: nsImage)
                }
            }
            if let image {
                await MainActor.run {
                    self.image = image
                }
            }
        }
    }
}
