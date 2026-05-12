//
//  ToolCallCard.swift
//  ExcalidrawZ
//
//  Created by Chocoford on 5/4/26.
//

import SwiftUI
import LLMCore
import SFSafeSymbols

/// Header row for a tool call inside an assistant round. The tool name is
/// always visible; raw arguments fold open on tap. While the LLM is mid
/// tool-calling round, `isActive` shimmers the name to signal "in flight".
///
/// Visual chassis (chevron, tinted background, padding, expand toggle)
/// lives in `ToolEventCard`; this struct just plugs in the call-specific
/// icon, title, accent, and the JSON-arg foldout body. When the user
/// denied this call from the approval prompt we draw a small "Denied"
/// badge on the right of the header so the round reads as "AI tried X,
/// you stopped it" rather than just "AI tried X."
struct ToolCallCard: View {
    let call: ToolCall
    var isActive: Bool = false
    /// True when the matching `.tool` observation message is the
    /// "User denied execution of …" text our agent injects on
    /// `.deny(...)`. Decided upstream by `AssistantRoundView` since
    /// the deny status lives in a sibling tool message, not on the
    /// `ToolCall` itself.
    var isDenied: Bool = false

    var body: some View {
        let isStreamingArguments = isActive && !isDenied
        ToolEventCard(
            icon: .hammerFill,
            // Resolve the snake_case `name` (LLM protocol payload) to the
            // tool's UI-friendly `displayName` via the sync cache. Falls
            // back to the raw name for tools the cache doesn't know
            // about (third-party / unregistered).
            title: ToolDisplayNameCache.displayName(for: call.name),
            accent: .purple,
            isShimmering: isActive && !isDenied,
            isExpandable: !isStreamingArguments,
            showsLoadingIndicator: isStreamingArguments,
            trailing: {
                if isDenied {
                    deniedBadge
                }
            }
        ) { isExpanded in
            if isExpanded, !isStreamingArguments, !call.arguments.isEmpty {
                Text(call.arguments)
            }
        }
    }

    /// "Denied" pill drawn on the right of the header. Mirrors the
    /// approval prompt's destructive accent so the user can scan the
    /// round and tell at a glance which calls they blocked.
    @ViewBuilder
    private var deniedBadge: some View {
        HStack(spacing: 3) {
            Image(systemSymbol: .handRaisedFill)
            Text("Denied")
        }
        .font(.caption2.weight(.medium))
        .foregroundStyle(.red)
    }
}
