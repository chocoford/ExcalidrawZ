//
//  PromptInputView+ActionBar.swift
//  ExcalidrawZ
//
//  Bottom controls of the prompt input: attachment menu (paperclip),
//  context-usage ring, model picker, and the primary send/stop button.
//  Extracted from `PromptInputView` so the main file stays focused on
//  composition + state and isn't dominated by control glue.
//
//  Everything here is an `extension` of `PromptInputView` and uses its
//  private state directly (`isImagePickerPresented`, `agentConfig`,
//  `pendingTierSelection`, etc.) — no parameters threaded through, just
//  the same scope split across files.
//

import SwiftUI
import ChocofordUI
import LLMKit
import LLMCore
import SFSafeSymbols

extension PromptInputView {
    /// Left half of the action row: attachment menu, context-usage ring,
    /// model picker. Wrapped in an HStack so the whole group can take a
    /// shared `buttonStyle` from the caller (`.accessoryBar` on macOS 14+,
    /// `.plain` below).
    @MainActor @ViewBuilder
    func actionBarLeading() -> some View {
        let _ = AIChatRenderDebug.hit("PromptInputView.actionBarLeading")

        HStack(spacing: 0) {
            attachmentMenu

            ContextUsageRing(
                model: activeModel,
                onTap: conversationID != nil && !isCompactingContext
                    ? { compactCurrentContext() }
                    : nil,
                usedTokens: nil
            )

            modelPicker
        }
    }

    /// Bottom-left attachment menu. Currently has only "Image" — clicking
    /// it opens the system file picker constrained to `UTType.image`,
    /// then appends accepted images to the prompt draft owner. Future
    /// entries (file uploads, canvas snapshots, etc.) drop in here as
    /// additional `Button`s.
    /// We deliberately don't use the `primaryAction:` closure form —
    /// the icon doesn't have a single "default" action; tapping it
    /// just opens the menu.
    @MainActor @ViewBuilder
    var attachmentMenu: some View {
        let _ = AIChatRenderDebug.hit("PromptInputView.attachmentMenu")

        Menu {
            Button {
                isImagePickerPresented = true
            } label: {
                Label(.localizable(.aiChatInputAttachmentMenuItemImage), systemSymbol: .photo)
            }
            .disabled(!canInsertImages)
        } label: {
            Image(systemSymbol: .paperclip)
                .resizable()
                .frame(height: 12)
        }
        .labelStyle(.iconOnly)
        .menuIndicator(.hidden)
        .fileImporter(
            isPresented: $isImagePickerPresented,
            allowedContentTypes: [.image],
            allowsMultipleSelection: true
        ) { result in
            handleImagePickerResult(result)
        }
    }

    /// Resolve the picked URLs into `PlatformImage`s and request the draft
    /// owner to append them. Each URL needs
    /// `startAccessingSecurityScopedResource` because `fileImporter`
    /// returns user-domain paths the app doesn't have ambient access to.
    /// Failures are swallowed per-file: a bad image shouldn't block the rest.
    @MainActor
    func handleImagePickerResult(_ result: Result<[URL], Error>) {
        guard canInsertImages else {
            alertToast(AIChatInputCapabilityError.noModelCanReadImages)
            return
        }
        guard case .success(let urls) = result else { return }
        guard !urls.isEmpty else { return }
        guard upgradeModelForImageInputIfNeeded() else {
            alertToast(
                AIChatInputCapabilityError.noModelCanReadImages
            )
            return
        }
        var images: [PendingPastedImage] = []
        for url in urls {
            let didStart = url.startAccessingSecurityScopedResource()
            defer {
                if didStart { url.stopAccessingSecurityScopedResource() }
            }
            guard let image = imageFromFileURL(url) else { continue }
            images.append(PendingPastedImage(id: UUID(), image: image))
        }
        aiChatState.requestAppendDraftImages(images)
    }

    @MainActor @ViewBuilder
    var modelPicker: some View {
        let _ = AIChatRenderDebug.hit("PromptInputView.modelPicker")

        // Agent config hasn't loaded → show a quiet placeholder. Loading is fast
        // (one HTTP round-trip on first appearance) so a permanent skeleton would
        // be visual noise; we just render the active model name disabled.
        let models = AIChatRenderDebug.measure("prompt.modelPicker.models") {
            (agentConfig?.allowedModels ?? [])
                .filter { canShowModelInPicker($0) }
        }
        let tiers = ExcalidrawModelTier.pickerOrder.filter { tier in
            models.contains { $0.excalidrawTier == tier }
        }
        let activeTier = activeModel.excalidrawTier ?? selectedTierBeforeFallback
        Menu {
            ForEach(tiers) { tier in
                Button {
                    pickTier(tier)
                } label: {
                    if tier == activeTier {
                        Label(tier.name, systemSymbol: .checkmark)
                    } else {
                        Text(tier.name)
                    }
                }
                .disabled(!canSelectTier(tier))
            }
        } label: {
            HStack(spacing: 4) {
                Text(activeModel.excalidrawTierName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
        }
        .menuIndicator(.visible)
        .disabled(tiers.isEmpty)
    }

    /// Route a tier pick to the right place: existing conversations get a
    /// stored override (so reopening that thread restores the pick); fresh
    /// chats just stage it in `pendingTierSelection` and get committed
    /// when `startSend` mints the conversation id.
    @MainActor
    func pickTier(_ tier: ExcalidrawModelTier) {
        guard canSelectTier(tier) else { return }

        if let id = conversationID {
            prefs.setTier(tier, for: id)
        } else {
            pendingTierSelection = tier
        }
    }

    @MainActor
    func canSelectTier(_ tier: ExcalidrawModelTier) -> Bool {
        let models = agentConfig?.allowedModels ?? []
        return models.contains { model in
            model.excalidrawTier == tier && canSelectModel(model)
        }
    }

    func loadAgentConfigIfNeeded() async {
        guard agentConfig == nil else { return }
        do {
            let config = try await LLMClient.shared.getDomainAgentConfig(agentID: agentID)
            await MainActor.run {
                self.agentConfig = config
            }
        } catch {
            alertToast(
                .init(
                    displayMode: .hud,
                    type: .error(.red),
                    title: String(
                        localizable: .aiChatErrorLoadAgentConfigFailed(
                            error.localizedDescription
                        )
                    ),
                )
            )
        }
    }

    // MARK: - Primary action button

    /// True when the assistant is currently generating. Drives the icon swap
    /// (arrow ↔ stop) and gates whether `sendMessage` enqueues vs sends now.
    var isGenerating: Bool {
        currentTask != nil || isConversationStreaming
    }

    private var isConversationStreaming: Bool {
        guard let conversationID else { return false }
        return llmState.isRunning(conversationID: conversationID)
    }

    var hasInputText: Bool {
        // "Has input" now also counts pasted images even if the user
        // typed no prose. A message with just a screenshot and no
        // accompanying text is a legitimate send.
        draftHasContent
    }

    /// Shows stop only when generating *and* the input is empty. If the user
    /// is mid-typing a follow-up while a reply streams, we keep the send glyph
    /// — that click queues the message without interrupting the live stream.
    var primaryActionIsStop: Bool {
        isGenerating && !hasInputText
    }

    @ViewBuilder
    func primaryActionButton() -> some View {
        let _ = AIChatRenderDebug.hit("PromptInputView.primaryActionButton")

        Button {
            if primaryActionIsStop {
                cancelCurrentGeneration()
            } else {
                draftSendRequestToken += 1
            }
        } label: {
            if #available(macOS 14.0, *) {
                Image(systemSymbol: primaryActionIsStop ? .stopFill : .arrowUp)
                    .frame(width: 16, height: 16)
                    .contentTransition(.symbolEffect(.replace))
            } else {
                Image(systemSymbol: primaryActionIsStop ? .stopFill : .arrowUp)
                    .frame(width: 16, height: 16)
            }
        }
        .modernButtonStyle(style: .glass, shape: .circle)
        // Stop is always enabled while generating. Send needs text.
        .disabled(!primaryActionIsStop && !hasInputText)
    }
}
