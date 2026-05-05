//
//  ToolCallCard.swift
//  ExcalidrawZ
//
//  Created by Chocoford on 5/4/26.
//

import SwiftUI
import LLMCore
import Shimmer

/// Header row for a tool call inside an assistant round. The tool name is
/// always visible; raw arguments fold open on tap. While the LLM is mid
/// tool-calling round, `isActive` shimmers the name to signal "in flight".
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
