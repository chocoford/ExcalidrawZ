//
//  PendingQueueView.swift
//  ExcalidrawZ
//
//  Stack of "queued" rows showing user messages typed *during* a streaming
//  reply. The send pipeline drains the queue FIFO once the in-flight reply
//  finishes; this view just renders the current state and lets the user
//  pull items back out before they hit the wire.
//
//  State lives on the host (AIChatView / AIChatIslandView) because the two
//  callers want different placement and styling for the queue — inspector
//  has plenty of room to sit it above the input box flush; the island is
//  width-constrained and may want a more compact treatment. Keeping the
//  state on the host means each can compose the view however it likes
//  while `PromptInputView` stays focused on the input chrome and the
//  send/cancel mechanics.
//

import SwiftUI
import SFSafeSymbols
import LLMCore

/// A single waiting message. UUID id keeps `ForEach` row identity stable
/// across removals — duplicate text in the queue would collide on
/// hash-by-value identity and produce flicker / wrong-row deletions.
///
/// `files` carries any attachments that were on the input when the
/// queue was appended (image paste, etc.). They piggy-back through the
/// drain path the same way text does so a queued message looks the
/// same whether it was sent immediately or after the in-flight reply
/// finished.
struct PendingQueueMessage: Identifiable, Equatable {
    let id: UUID
    let text: String
    let files: [LLMCoreFile]

    init(id: UUID = UUID(), text: String, files: [LLMCoreFile] = []) {
        self.id = id
        self.text = text
        self.files = files
    }
}

/// Module-local type alias — keeps `PendingQueueView.swift` from
/// having to `import LLMCore` at the top just for one occurrence.
/// `ChatMessageContent.File` is `Equatable` (it's a `ContentModel`),
/// so the `Equatable` synthesis on `PendingQueueMessage` works.
typealias LLMCoreFile = LLMCore.ChatMessageContent.File

struct PendingQueueView: View {
    let messages: [PendingQueueMessage]
    /// Called when the user taps the per-row `x`. Host should remove the
    /// matching id from the source-of-truth array.
    let onRemove: (UUID) -> Void

    var body: some View {
        if !messages.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(messages) { item in
                    queuedMessageRow(item)
                        .transition(.asymmetric(
                            // Insert from below: feels like "queued just
                            // now". Remove upward: feels like "picked up
                            // to send" or "discarded".
                            insertion: .opacity.combined(with: .move(edge: .bottom)),
                            removal: .opacity.combined(with: .move(edge: .top))
                        ))
                    
                    if item != messages.last {
                        Divider()
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .compositingGroup()
            .animation(.smooth, value: messages)
            .background {
                if #available(macOS 26.0, iOS 26.0, *) {
                    RoundedRectangle(cornerRadius: 24)
                        .fill(.clear)
                        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 24))
                } else {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(.regularMaterial)
                }
            }
        }
    }

    @ViewBuilder
    private func queuedMessageRow(_ item: PendingQueueMessage) -> some View {
        HStack(spacing: 8) {
            Image(systemSymbol: .clockFill)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(item.text)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            Spacer(minLength: 0)
            Button {
                onRemove(item.id)
            } label: {
                Label(.localizable(.aiChatPendingQueueButtonRemove), systemSymbol: .trash)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .padding(4)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(.localizable(.aiChatPendingQueueButtonRemove))
        }
    }
}
