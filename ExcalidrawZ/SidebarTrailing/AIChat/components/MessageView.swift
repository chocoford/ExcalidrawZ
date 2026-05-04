//
//  MessageView.swift
//  LLMDemo
//
//  Created by Chocoford on 9/5/25.
//

import SwiftUI
import LLMCore
import LLMKit
import ChocofordUI
import ChocofordEssentials
import Shimmer

enum ChatMessageContentFileValue {
    case image(Image)
}

/// Renders standalone messages: user bubble, loading, error.
/// Assistant + tool messages are aggregated round-style by `AssistantRoundView`
/// in `AIChatView` — they never come through here, so no per-message AI actions.
struct MessageView: View {
    var message: ChatMessage

    var body: some View {
        switch message {
            case .loading:
                LoadingMessageRow()
            case .error(_, let error):
                ErrorMessageRow(error: error)
            case .content(let content):
                if content.role == .user {
                    HStack {
                        Spacer()
                        VStack(alignment: .trailing, spacing: 4) {
                            contentBubble(message: content)
                        }
                    }
                }
                // assistant / tool / system / developer roles are handled
                // round-style upstream; never rendered here.
        }
    }

    @MainActor @ViewBuilder
    private func contentBubble(message: ChatMessageContent) -> some View {
        if let text = message.content, !text.isEmpty {
            SmoothStreamingText(target: text)
                .padding()
                .background(Color.gray.opacity(0.2))
                .cornerRadius(12)
        }

        if let usage = message.usage {
            HStack(spacing: 4) {
                Image(systemName: "bolt.circle")
                Text(usage.consumed.formatted())
            }
            .font(.footnote)
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .background {
                Capsule().fill(.regularMaterial)
            }
        }

        HStack(spacing: 6) {
            let imageFiles = (message.files ?? []).filter {
                if case .base64EncodedImage = $0 {
                    return true
                }
                if case .image = $0 {
                    return true
                }
                return false
            }
            ForEach(imageFiles, id: \.self) { file in
                MessageImageView(file: file)
            }
        }
    }
}

// MARK: - Subviews

struct LoadingMessageRow: View {
    var body: some View {
        Text("Thinking")
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding()
            .background(Color.gray.opacity(0.2), in: RoundedRectangle(cornerRadius: 12))
            .shimmering(active: true)
    }
}

private struct ErrorMessageRow: View {
    let error: String

    var body: some View {
        Text(error)
            .padding()
            .foregroundStyle(.red)
            .background(Color.gray.opacity(0.2), in: RoundedRectangle(cornerRadius: 12))
    }
}

/// Tool call card. Header (icon + name) is always visible; arguments fold.
/// `isActive` shimmers the name while the LLM is mid tool-calling round.
struct ToolCallCard: View {
    let call: ToolCall
    var isActive: Bool = false

    @State private var isExpanded: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button {
                isExpanded.toggle()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.purple)
                    Image(systemName: "hammer.fill")
                        .foregroundStyle(.purple)
                        .font(.caption)
                    Text(call.name)
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.purple)
                        .shimmering(active: isActive)
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded, !call.arguments.isEmpty {
                Text(call.arguments)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .padding(.leading, 22)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.purple.opacity(0.1))
        .cornerRadius(8)
    }
}

/// Tool result card. Header always visible; body shown inline (per spec the result
/// belongs visually under its parent toolCall — that join is a list-level concern,
/// for now this stands on its own row).
struct ToolResultCard: View {
    let content: ChatMessageContent

    @State private var isExpanded: Bool = false

    private var imageFiles: [ChatMessageContent.File] {
        (content.files ?? []).filter { file in
            switch file {
                case .base64EncodedImage, .image:
                    return true
            }
        }
    }

    var body: some View {
        let resolvedContent = content.content ?? ""
        VStack(alignment: .leading, spacing: 4) {
            Button {
                isExpanded.toggle()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.green)
                    Image(systemName: "eye.fill")
                        .foregroundStyle(.green)
                        .font(.caption)
                    Text("Tool result")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.green)
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if !resolvedContent.isEmpty {
                SmoothStreamingText(target: resolvedContent)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 22)
                    .lineLimit(isExpanded ? nil : 4)
            }

            // Image attachments — multimodal tools (e.g. canvas screenshot) ship
            // their visual payload here. Always shown so the user can confirm
            // what the model is "seeing", regardless of expand state.
            if !imageFiles.isEmpty {
                HStack(spacing: 6) {
                    ForEach(imageFiles, id: \.self) { file in
                        MessageImageView(file: file)
                    }
                }
                .padding(.leading, 22)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.green.opacity(0.1))
        .cornerRadius(8)
    }
}

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
