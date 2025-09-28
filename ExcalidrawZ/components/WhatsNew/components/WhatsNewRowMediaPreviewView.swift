//
//  WhatsNewRowMediaPreviewView.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 8/5/25.
//

import SwiftUI
import AVKit

struct WhatsNewRowMediaPreviewView: View {
    var url: URL?
    
    init(url: URL?) {
        self.url = url
    }
    
    @State private var mediaPreviewImage: Image?
    
    var body: some View {
        ZStack {
            if let mediaPreviewImage {
                mediaPreviewImage
                    .resizable()
                    .scaledToFit()
            } else {
                Color.black
            }
        }
        .frame(width: 120)
        .frame(maxHeight: 120)
        .overlay {
            Image(systemSymbol: .playCircleFill)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: 60, maxHeight: 60)
                .padding(10)
                .blendMode(.difference)
        }
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .contentShape(Rectangle())
//        .onAppear {
//            if let mediaURL = url {
//                let asset = AVAsset(url: mediaURL)
//                let imageGenerator = AVAssetImageGenerator(asset: asset)
//                imageGenerator.appliesPreferredTrackTransform = true
//                
//                if #available(macOS 13.0,  *) {
//                    imageGenerator.generateCGImageAsynchronously(for: .zero) { cgImage, time, error in
//                        Task.detached {
//                            if let cgImage {
//                                let image = Image(cgImage: cgImage)
//                                await MainActor.run {
//                                    self.mediaPreviewImage = image
//                                }
//                            }
//                        }
//                    }
//                } else {
//                    // Fallback on earlier versions
//                }
//            }
//        }
    }
}

