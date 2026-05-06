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
///
/// Shares the chevron / tinted-background / expand-toggle chassis with
/// `ToolCallCard` via `ToolEventCard`. This struct just supplies the
/// observe-result icon + green accent, and chooses what to keep pinned
/// vs. fold-on-collapse inside the body builder.
struct ToolResultCard: View {
    let content: ChatMessageContent

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
        ToolEventCard(
            icon: .eyeFill,
            title: "Observe result",
            accent: .green
        ) { isExpanded in
            
            if !resolvedContent.isEmpty && isExpanded || !imageFiles.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    if !resolvedContent.isEmpty && isExpanded {
                        Text(resolvedContent)
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
        }
    }
}
