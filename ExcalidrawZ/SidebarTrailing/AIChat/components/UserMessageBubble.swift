//
//  UserMessageBubble.swift
//  ExcalidrawZ
//
//  Created by Chocoford on 5/4/26.
//

import SwiftUI
import LLMCore
import SFSafeSymbols

/// Right-aligned chat bubble for a `user` role message, plus any attached
/// images and the per-message usage chip.
struct UserMessageBubble: View {
    let content: ChatMessageContent
    /// Optional revert handler — called with the user message's id. The
    /// host walks back to the matching `.aiPre` checkpoint, restores the
    /// file, prefills the input box with this message's text, and
    /// (eventually) truncates the conversation. When `nil`, the revert
    /// button is hidden (e.g. the message has no anchored pre-checkpoint
    /// or the host doesn't support revert).
    var onRevert: ((String) -> Void)?

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
                        // Inline action bar — right-aligned to match the
                        // bubble. Only renders when there's something
                        // useful in it.
                        if onRevert != nil {
                            actionBar
                        }
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

    @ViewBuilder
    private var actionBar: some View {
        HStack(spacing: 4) {
            if let onRevert {
                Button {
                    onRevert(content.id)
                } label: {
                    Label("Revert", systemSymbol: .arrowUturnBackward)
                        .labelStyle(.iconOnly)
                        .font(.caption)
                }
                .buttonStyle(.text(size: .small, square: true))
                .foregroundStyle(.secondary)
                .help("Revert canvas to before this message and reload its text into the input box.")
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
