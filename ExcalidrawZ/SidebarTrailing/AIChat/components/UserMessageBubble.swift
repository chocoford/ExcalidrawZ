//
//  UserMessageBubble.swift
//  ExcalidrawZ
//
//  Created by Chocoford on 5/4/26.
//

import SwiftUI
import LLMCore

/// Right-aligned chat bubble for a `user` role message, plus any attached
/// images and the per-message usage chip.
struct UserMessageBubble: View {
    let content: ChatMessageContent
    @State private var isPresented = false

    var body: some View {
        VStack(spacing: 0) {
            Color.clear
                .frame(height: isPresented ? 0 : 20)
            if isPresented {
                HStack {
                    Spacer()
                    VStack(alignment: .trailing, spacing: 4) {
                        bubbleContents
                    }
                }
                .opacity(isPresented ? 1 : 0)
            }
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                withAnimation(.easeOut) {
                    isPresented = true
                }
            }
        }
    }

    @MainActor @ViewBuilder
    private var bubbleContents: some View {
        if let text = content.content, !text.isEmpty {
            if #available(macOS 14.0, *) {
                SmoothStreamingText(target: text)
                    .padding(10)
                    .background(Color.accentColor.gradient.secondary)
                    .cornerRadius(20)
            } else {
                SmoothStreamingText(target: text)
                    .padding(10)
                    .background(Color.secondary.gradient)
                    .cornerRadius(20)
            }
        }

//        if let usage = content.usage {
//            HStack(spacing: 4) {
//                Image(systemName: "bolt.circle")
//                Text(usage.consumed.formatted())
//            }
//            .font(.footnote)
//            .padding(.horizontal, 4)
//            .padding(.vertical, 2)
//            .background {
//                Capsule().fill(.regularMaterial)
//            }
//        }

        let imageFiles = (content.files ?? []).filter { file in
            switch file {
                case .base64EncodedImage, .image:
                    return true
            }
        }
        if !imageFiles.isEmpty {
            HStack(spacing: 6) {
                ForEach(imageFiles, id: \.self) { file in
                    MessageImageView(file: file)
                }
            }
        }
    }
}
