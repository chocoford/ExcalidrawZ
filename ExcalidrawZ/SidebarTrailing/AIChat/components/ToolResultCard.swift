//
//  ToolResultCard.swift
//  ExcalidrawZ
//
//  Created by Chocoford on 5/4/26.
//

import SwiftUI
import LLMCore

/// Result emitted by a tool. Header always visible; text body shown inline
/// (truncated to 4 lines until expanded). Image attachments — multimodal tools
/// like the canvas screenshot ship their visual payload here — render
/// regardless of expand state so the user can confirm what the model "sees".
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
                    Image(systemSymbol: .chevronRight)
                        .rotationEffect(isExpanded ? .degrees(90) : .zero)
                    Image(systemSymbol: .eyeFill)
                    Text("Observe result")
                        .fontWeight(.semibold)
                    Spacer()
                }
                .foregroundStyle(.green)
                .font(.caption)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if !resolvedContent.isEmpty && isExpanded {
                SmoothStreamingText(target: resolvedContent)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 22)
                    // .lineLimit(isExpanded ? nil : 4)
            }

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
