//
//  PromptInputView.swift
//  ExcalidrawZ
//
//  Created by Chocoford on 1/10/26.
//
//  The prompt block at the bottom of every chat surface (inspector +
//  island). Owns input text + paste / pasted images, the send Task,
//  and the current model pick. The implementation is split across
//  files; this one keeps the struct definition, state, and
//  composition (`body` / `content`):
//
//   - `PromptInputStyle.swift` — visual presets + backdrop sentinel
//   - `PromptInputView+ActionBar.swift` — bottom controls (paperclip,
//     ring, model picker, send/stop button)
//   - `PromptInputView+InputField.swift` — TextArea + paste plumbing
//   - `PromptInputView+Send.swift` — sendMessage / startSend / compact /
//     queue drainer / auto-compact threshold check
//
//  All extensions reach into the struct's state directly — that's why
//  most stored properties below aren't `private` (Swift's `private`
//  doesn't reach extensions in other files). They stay file-internal
//  via the module boundary instead.
//

import SwiftUI
import UniformTypeIdentifiers

import ChocofordUI
import LLMKit
import LLMCore

struct ExcalidrawChatInvocationContext: ChatInvocationContext {
    var currentFileData: Data?
    var canvasTarget: ExcalidrawCoordinatorRegistry.CanvasTarget
    var selectedElementIDs: [String]?
    var currentFileID: UUID?
}

struct PromptInputView<Background: View>: View {
    @EnvironmentObject var llmState: LLMStateObject
    @EnvironmentObject var fileState: FileState
    @EnvironmentObject var aiChatState: AIChatState
    @Environment(\.alertToast) var alertToast

    @Binding var conversationID: String?
    /// Pending-send queue, owned by the host so they can render the
    /// `PendingQueueView` wherever (and however) they want — inspector
    /// vs island place it differently. PromptInputView appends here when
    /// the user sends mid-stream, drains here when an in-flight reply
    /// finishes, and clears here on stop.
    @Binding var pendingQueue: [PendingQueueMessage]
    let style: PromptInputStyle<Background>

    init(
        conversationID: Binding<String?>,
        pendingQueue: Binding<[PendingQueueMessage]>,
        style: PromptInputStyle<Background>
    ) {
        self._conversationID = conversationID
        self._pendingQueue = pendingQueue
        self.style = style
    }

    @State var inputText: String = ""
    /// Side-state mirror for image attachments pasted into the input.
    /// `inputText` only carries the `[image:<UUID>]` placeholders that
    /// `PastedImageToken.plainText` produces — the actual image bytes
    /// live here keyed by token id, and we reconcile the two on send.
    /// See [PromptInputView+ImagePaste.swift](PromptInputView+ImagePaste.swift)
    /// for the full data flow.
    @State var pastedImages: [PendingPastedImage] = []
    /// Drives the system image-picker sheet from the attachment menu.
    /// Selected files flow through the same `pastedImages` side-state
    /// as paste, so once they're added the rest of the pipeline (send,
    /// thumbnail strip, persist) is unchanged.
    @State var isImagePickerPresented: Bool = false
    @State var agentConfig: DomainAgentConfigResponse?

    /// User's model pick made *before* a conversation has been created
    /// (i.e., a fresh chat). Promoted to a per-conversation override in
    /// `AIChatPreferences` the moment `startSend` mints a conversation id.
    /// Once the conversation exists, the picker writes straight to prefs.
    @State var pendingModelSelection: SupportedModel?

    /// Global default + per-conversation overrides, persisted across
    /// launches. Drives `activeModel` and reflected back from picker
    /// taps / Settings changes.
    @ObservedObject var prefs = AIChatPreferences.shared

    /// In-flight send task. While non-nil, the assistant is generating a reply.
    /// Cancelling this task propagates Swift cooperative cancellation through
    /// `llmState.sendMessage`'s stream consumer, which terminates the request.
    @State var currentTask: Task<Void, Never>?

    @FocusState var isInputFocused: Bool

    /// Server-side agent identifier; the backend resolves system prompt + agent
    /// config from this. Tools list still ships from the client because tool
    /// implementations are local. Pulled from `ExcalidrawAgentConfig` so this
    /// view, the persistence layer's restore path, and any future agent
    /// callers can't drift apart.
    var agentID: String { ExcalidrawAgentConfig.agentID }

    /// Resolved model used for the next request, in priority order:
    ///   1. Per-conversation override stored in `AIChatPreferences`
    ///   2. Pending pick made before a conversation exists
    ///   3. User's global default (Settings → AI)
    /// Picker writes directly into either (1) or (2); (3) is mutated
    /// from Settings only.
    var activeModel: SupportedModel {
        if let stored = prefs.model(for: conversationID) {
            return stored
        }
        if let pending = pendingModelSelection {
            return pending
        }
        return prefs.defaultModel
    }

    var conversation: Conversation? {
        guard let conversationID else { return nil }
        return llmState.getConversation(by: conversationID)
    }

    var currentFileData: Data? {
        get async throws {
            let canvasTarget: ExcalidrawCoordinatorRegistry.CanvasTarget = {
                switch fileState.currentActiveFile {
                    case .collaborationFile:
                        .collaboration
                    default:
                        .normal
                }
            }()
            return try await CurrentExcalidrawDataResolver.resolve(
                fileState: fileState,
                canvasTarget: canvasTarget
            )
        }
    }

    /// True when this view's conversation is currently being compacted.
    /// Derived from the app-scoped `AIChatState.compactingConversationIDs`
    /// set rather than a local @State so `AIChatView` can render the
    /// "compacting…" indicator off the same publisher — a single
    /// PromptInputView can't reach the chat list above it.
    var isCompactingContext: Bool {
        aiChatState.isCompacting(conversationID: conversationID)
    }

    var body: some View {
        ZStack {
            if #available(macOS 26.0, iOS 26.0, *) {
                content()
            } else {
                content()
                    .padding(8)
            }
        }
        .task {
            await loadAgentConfigIfNeeded()
        }
        // Consume one-shot draft prefill requests from the host (e.g.,
        // the per-user-message Revert action). Token-based so a second
        // revert with identical text still triggers the .onChange.
        .onChange(of: aiChatState.draftRequest?.token) { _ in
            guard let req = aiChatState.draftRequest else { return }
            inputText = req.text
            pastedImages = PastedImageHelpers.pendingImages(from: req.files)
            isInputFocused = true
        }
        .onChange(of: aiChatState.editCancelToken) { _ in
            inputText = ""
            pastedImages = []
            isInputFocused = false
        }
    }

    @ViewBuilder
    private func content() -> some View {
        VStack(spacing: 6) {
            if style.showsLowCreditsBanner {
                VStack(spacing: 0) {
                    LowCreditsBannerView(peekBottom: 18)
                        .padding(.horizontal, 10)
                        .font(.caption)
                        .offset(y: 18)

                    inputBox
                }
            } else {
                inputBox
            }

            HStack {
                if #available(macOS 14.0, iOS 17.0, *) {
                    actionBarLeading()
                        .buttonBorderShape(.roundedRectangle(radius: 6))
                        .buttonStyle(.accessoryBar)
                } else {
                    actionBarLeading()
                        .buttonStyle(.plain)
                }

                Spacer()

                primaryActionButton()
            }
            .controlSize(.large)
        }
    }
}

// MARK: - Default-style convenience

extension PromptInputView where Background == PlatformDefaultPromptBackground {
    /// Style-less convenience init — picks `.inspector` so existing call
    /// sites keep working without forcing the caller to think about
    /// `Background` at all.
    init(
        conversationID: Binding<String?>,
        pendingQueue: Binding<[PendingQueueMessage]>
    ) {
        self.init(
            conversationID: conversationID,
            pendingQueue: pendingQueue,
            style: .inspector
        )
    }
}
