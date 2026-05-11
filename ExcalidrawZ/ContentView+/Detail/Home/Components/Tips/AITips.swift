//
//  AITips.swift
//  ExcalidrawZ
//
//  Created by Codex on 5/11/26.
//

import SwiftUI
import MarkdownUI

extension HomeTipItemView {
    static let ai = HomeTipItemView(
        title: "AI Chat",
        message: "Ask AI to read, explain, and edit your current canvas.",
        icon: .sparkles
    ) {
        AITipsDetail()
    }
}

struct AITipsDetail: View {
    var body: some View {
        TipDetailContainer(spacing: 24) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Work with AI on your canvas")
                    .font(.title)

                Text("AI Chat is designed for the drawing you are already viewing, so the conversation and generated changes stay tied to that file.")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Markdown(
                """
                ### Start from the AI tab

                Open a drawing, then switch to the AI tab from the trailing controls. Ask AI to summarize the canvas, clean up a diagram, generate new elements, or explain what is already on the board.

                ### Give it useful context

                You can describe the result you want in natural language. When the prompt depends on external material, attach images or screenshots so AI can use them together with the current canvas.

                ### Review generated changes

                AI edits are applied to the current file conversation. Review the result before continuing, and use the revert action on AI-made canvas changes when a result is not what you wanted.

                ### Prompt ideas

                - Organize this flowchart into clear sections.
                - Turn this rough sketch into a tidy architecture diagram.
                - Explain this canvas and list the open questions.
                - Add labels and make the relationships easier to follow.
                """
            )
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
