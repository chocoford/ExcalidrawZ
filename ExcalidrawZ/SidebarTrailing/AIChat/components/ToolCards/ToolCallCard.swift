//
//  ToolCallCard.swift
//  ExcalidrawZ
//
//  Created by Chocoford on 5/4/26.
//

import SwiftUI
import LLMCore

/// Header row for a tool call inside an assistant round. The tool name is
/// always visible; raw arguments fold open on tap. While the LLM is mid
/// tool-calling round, `isActive` shimmers the name to signal "in flight".
///
/// Visual chassis (chevron, tinted background, padding, expand toggle)
/// lives in `ToolEventCard`; this struct just plugs in the call-specific
/// icon, title, accent, and the JSON-arg foldout body.
struct ToolCallCard: View {
    let call: ToolCall
    var isActive: Bool = false

    var body: some View {
        ToolEventCard(
            icon: .hammerFill,
            title: call.name,
            accent: .purple,
            isShimmering: isActive
        ) { isExpanded in
            if isExpanded, !call.arguments.isEmpty {
                Text(call.arguments)
            }
        }
    }
}
