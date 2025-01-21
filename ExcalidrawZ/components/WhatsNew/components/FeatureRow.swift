//
//  FeatureRow.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 1/21/25.
//

import SwiftUI
import AVKit

struct WhatsNewFeatureRow: View {
    
    var icon: AnyView
    var content: AnyView
    var mediaURL: URL?
    
    init<Icon: View, Content: View>(
        @ViewBuilder icon: () -> Icon,
        @ViewBuilder content: () -> Content
    ) {
        self.icon = AnyView(icon())
        self.content = AnyView(content())
    }
    
    
    init<ImageView: View>(
        title: LocalizedStringKey,
        description: LocalizedStringKey,
        appendMediaURL: URL? = nil,
        @ViewBuilder icon: () -> ImageView
    ) {
        self.init {
            icon()
        } content: {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(description).font(.caption).foregroundStyle(.secondary)
            }
        }
        self.mediaURL = appendMediaURL
    }
    
    init(
        title: LocalizedStringKey,
        description: LocalizedStringKey,
        icon: Image,
        appendMediaURL: URL? = nil
    ) {
        self.init(title: title, description: description, appendMediaURL: appendMediaURL) {
            icon.resizable()
        }
    }
    
    @State private var mediaPreviewImage: Image?
    
    
    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            icon
                .symbolRenderingMode(.multicolor)
                .scaledToFit()
                .frame(width: 68, height: 40, alignment: .center)
            
            content
            
            if mediaURL != nil {
                Rectangle()
                    .frame(width: 120, height: 1)
                    .opacity(0)
            }
        }
        .overlay(alignment: .trailing) {
            if let mediaURL {
                NavigationLink {
                    VideoPlayer(player: AVPlayer(url: mediaURL))
#if os(macOS)
                        .frame(width: 720, height: 500)
#endif
                } label: {
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
                }
                .buttonStyle(.borderless)
            }
        }
        .onAppear {
            if let mediaURL {
                let asset = AVAsset(url: mediaURL)
                let imageGenerator = AVAssetImageGenerator(asset: asset)
                imageGenerator.appliesPreferredTrackTransform = true
                
                if #available(macOS 13.0,  *) {
                    imageGenerator.generateCGImageAsynchronously(for: .zero) { cgImage, time, error in
                        Task.detached {
                            if let cgImage {
                                let image = Image(cgImage: cgImage)
                                await MainActor.run {
                                    self.mediaPreviewImage = image
                                }
                            }
                        }
                    }
                } else {
                    // Fallback on earlier versions
                }
            }
        }
    }
}
