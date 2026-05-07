//
//  PromptInputView.swift
//  ExcalidrawZ
//
//  Created by Chocoford on 1/10/26.
//

import SwiftUI

import ChocofordUI
import LLMKit
import LLMCore

struct ExcalidrawChatInvocationContext: ChatInvocationContext {
    var currentFileData: Data?
    var canvasTarget: ExcalidrawCoordinatorRegistry.CanvasTarget
    var selectedElementIDs: [String]?
}

/// Visual knobs for `PromptInputView`. Lets callers tune the prompt block to
/// the chrome it's embedded in — the inspector panel wants prominent shadow,
/// border and the low-credits banner; the floating island shares the same
/// chassis but trims the chrome.
///
/// `Background` is a concrete `View` type rather than `AnyView` so the input
/// box's `.background { … }` propagates layout proposals normally — type
/// erasure was creating a class of subtle frame-clipping issues. The platform
/// default is materialized as a typed sentinel view (`PlatformDefaultPromptBackground`)
/// so presets that want it don't need a closure.
struct PromptInputStyle<Background: View> {
    /// Whether the "Only N credits left" hint above the input is visible.
    /// Hosts with limited vertical space usually turn this off.
    var showsLowCreditsBanner: Bool

    /// Corner radius for the input field and its border/banner.
    var cornerRadius: CGFloat

    /// Drop-shadow under the input field. `nil` disables the shadow entirely.
    var shadow: ShadowSpec?

    /// Hairline border around the input field. `nil` disables the border.
    var border: BorderSpec?

    /// View painted behind the input field. The view receives the input's
    /// frame; include whatever shape/clip you want it to take. Typically a
    /// `RoundedRectangle(cornerRadius: cornerRadius)` so the corners match
    /// `border`.
    var background: Background

    /// Caller supplies a custom backdrop via `@ViewBuilder`.
    init(
        showsLowCreditsBanner: Bool = true,
        cornerRadius: CGFloat = 20,
        shadow: ShadowSpec? = ShadowSpec(opacity: 0.2, radius: 4),
        border: BorderSpec? = BorderSpec(lineWidth: 0.5),
        @ViewBuilder background: () -> Background
    ) {
        self.showsLowCreditsBanner = showsLowCreditsBanner
        self.cornerRadius = cornerRadius
        self.shadow = shadow
        self.border = border
        self.background = background()
    }

    struct ShadowSpec {
        var color: Color = .black
        var opacity: Double = 0.2
        var radius: CGFloat = 4

        init(color: Color = .black, opacity: Double = 0.2, radius: CGFloat = 4) {
            self.color = color
            self.opacity = opacity
            self.radius = radius
        }
    }

    struct BorderSpec {
        var lineWidth: CGFloat = 0.5
    }
}

// MARK: - Platform-default convenience

extension PromptInputStyle where Background == PlatformDefaultPromptBackground {
    /// Closure-less init: backdrop falls back to `PlatformDefaultPromptBackground`,
    /// which paints glass on macOS 26+ / iOS 26+ and regularMaterial below.
    /// Most call sites should use this — only reach for the `@ViewBuilder`
    /// init when you actually need a non-default backdrop.
    init(
        showsLowCreditsBanner: Bool = true,
        cornerRadius: CGFloat = 20,
        shadow: ShadowSpec? = ShadowSpec(opacity: 0.2, radius: 4),
        border: BorderSpec? = BorderSpec(lineWidth: 0.5)
    ) {
        self.init(
            showsLowCreditsBanner: showsLowCreditsBanner,
            cornerRadius: cornerRadius,
            shadow: shadow,
            border: border,
            background: {
                PlatformDefaultPromptBackground(cornerRadius: cornerRadius)
            }
        )
    }

    /// Default — used by `AIChatView` inside the inspector. Full chrome,
    /// shows the credits hint, platform-default background.
    static var inspector: PromptInputStyle<PlatformDefaultPromptBackground> {
        PromptInputStyle()
    }

    /// Tuned for `AIChatIslandView`. Same backdrop as the inspector (so the
    /// glass rim on macOS 26+ gives the text its visual padding), just with
    /// the credits banner / shadow trimmed because the island provides its
    /// own outer chrome.
    static var island: PromptInputStyle<PlatformDefaultPromptBackground> {
         PromptInputStyle(
             showsLowCreditsBanner: false,
             cornerRadius: 24,
             shadow: .init(color: .clear, radius: 0),
             border: BorderSpec(lineWidth: 0)
         )
    }
}

/// Glass on macOS 26+ / iOS 26+, `regularMaterial` below. Materialized as a
/// concrete `View` so `PromptInputStyle` can stay generic without falling
/// back to `AnyView` — the input field's `.background` then propagates
/// layout proposals cleanly.
struct PlatformDefaultPromptBackground: View {
    let cornerRadius: CGFloat

    var body: some View {
        if #available(macOS 26.0, iOS 26.0, *) {
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(Color.textBackgroundColor)
                .glassEffect(in: RoundedRectangle(cornerRadius: cornerRadius))
        } else {
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(.regularMaterial)
        }
    }
}

struct PromptInputView<Background: View>: View {
    @EnvironmentObject private var llmState: LLMStateObject
    @EnvironmentObject private var fileState: FileState
    @EnvironmentObject private var aiChatState: AIChatState
    @Environment(\.alertToast) private var alertToast

    @Binding var conversationID: String?
    /// Pending-send queue, owned by the host so they can render the
    /// `PendingQueueView` wherever (and however) they want — inspector
    /// vs island place it differently. PromptInputView appends here when
    /// the user sends mid-stream, drains here when an in-flight reply
    /// finishes, and clears here on stop.
    @Binding var pendingQueue: [PendingQueueMessage]
    private let style: PromptInputStyle<Background>

    init(
        conversationID: Binding<String?>,
        pendingQueue: Binding<[PendingQueueMessage]>,
        style: PromptInputStyle<Background>
    ) {
        self._conversationID = conversationID
        self._pendingQueue = pendingQueue
        self.style = style
    }

    @State private var inputText: String = ""
    @State private var agentConfig: DomainAgentConfigResponse?

    /// User's model pick made *before* a conversation has been created
    /// (i.e., a fresh chat). Promoted to a per-conversation override in
    /// `AIChatPreferences` the moment `startSend` mints a conversation id.
    /// Once the conversation exists, the picker writes straight to prefs.
    @State private var pendingModelSelection: SupportedModel?

    /// Global default + per-conversation overrides, persisted across
    /// launches. Drives `activeModel` and reflected back from picker
    /// taps / Settings changes.
    @ObservedObject private var prefs = AIChatPreferences.shared

    /// In-flight send task. While non-nil, the assistant is generating a reply.
    /// Cancelling this task propagates Swift cooperative cancellation through
    /// `llmState.sendMessage`'s stream consumer, which terminates the request.
    @State private var currentTask: Task<Void, Never>?


    @FocusState private var isInputFocused: Bool

    /// Server-side agent identifier; the backend resolves system prompt + agent
    /// config from this. Tools list still ships from the client because tool
    /// implementations are local. Pulled from `ExcalidrawAgentConfig` so this
    /// view, the persistence layer's restore path, and any future agent
    /// callers can't drift apart.
    private var agentID: String { ExcalidrawAgentConfig.agentID }

    /// Resolved model used for the next request, in priority order:
    ///   1. Per-conversation override stored in `AIChatPreferences`
    ///   2. Pending pick made before a conversation exists
    ///   3. User's global default (Settings → AI)
    /// Picker writes directly into either (1) or (2); (3) is mutated
    /// from Settings only.
    private var activeModel: SupportedModel {
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
            isInputFocused = true
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
                Menu {
                    
                } label: {
                    Button {
                        
                    } label: {
                        Label("", systemSymbol: .paperclip)
                    }
                } primaryAction: {
                    
                }
                .labelStyle(.iconOnly)
                .menuIndicator(.hidden)
                .modernButtonStyle(style: .plain, shape: .circle)
                
                modelPicker

                Spacer()

                primaryActionButton()
            }
            .controlSize(.large)
        }
    }

    
    @ViewBuilder
    private var modelPicker: some View {
        // Agent config hasn't loaded → show a quiet placeholder. Loading is fast
        // (one HTTP round-trip on first appearance) so a permanent skeleton would
        // be visual noise; we just render the active model name disabled.
        let models = agentConfig?.allowedModels ?? []
        Menu {
            ForEach(models, id: \.rawValue) { model in
                Button {
                    pickModel(model)
                } label: {
                    if model == activeModel {
                        Label(model.displayName, systemSymbol: .checkmark)
                    } else {
                        Text(model.displayName)
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(activeModel.displayName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Image(systemSymbol: .chevronDown)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .modernButtonStyle(style: .plain)
        .menuIndicator(.visible)
        .disabled(models.isEmpty)
    }

    /// Route a model pick to the right place: existing conversations get a
    /// stored override (so reopening that thread restores the pick); fresh
    /// chats just stage it in `pendingModelSelection` and get committed
    /// when `startSend` mints the conversation id.
    private func pickModel(_ model: SupportedModel) {
        if let id = conversationID {
            prefs.setModel(model, for: id)
        } else {
            pendingModelSelection = model
        }
    }

    private func loadAgentConfigIfNeeded() async {
        guard agentConfig == nil else { return }
        do {
            let config = try await LLMClient.shared.getDomainAgentConfig(agentID: agentID)
            await MainActor.run {
                self.agentConfig = config
            }
        } catch {
            print("Failed to load agent config: \(error)")
        }
    }
    

    /// Input box layered to honor the active `PromptInputStyle`: background,
    /// corner-rounded border, optional shadow. `style.background` is a
    /// concrete `View` (no `AnyView`, no `Optional`), so the modifier chain
    /// is a single straight pass — SwiftUI's layout proposals reach the
    /// backdrop intact.
    ///
    /// `.shadow` is applied via a real `if let` rather than the previous
    /// `.shadow(color: .clear, radius: 0)` fallback: SwiftUI still spins up
    /// a shadow effect layer even when all parameters are zero-equivalent,
    /// which left a faint compositing artifact in island mode.
    @ViewBuilder
    private var inputBox: some View {
        let radius = style.cornerRadius
        let core = inputField()
            .overlay {
                if let border = style.border {
                    RoundedRectangle(cornerRadius: radius)
                        .stroke(.separator, lineWidth: border.lineWidth)
                }
            }
        
        if let shadow = style.shadow {
            core
                .compositingGroup()
                .shadow(
                    color: shadow.color.opacity(shadow.opacity),
                    radius: shadow.radius
                )
        } else {
            core
        }
    }

    /// True when the assistant is currently generating. Drives the icon swap
    /// (arrow ↔ stop) and gates whether `sendMessage` enqueues vs sends now.
    private var isGenerating: Bool {
        currentTask != nil
    }

    private var hasInputText: Bool {
        !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Shows stop only when generating *and* the input is empty. If the user
    /// is mid-typing a follow-up while a reply streams, we keep the send glyph
    /// — that click queues the message without interrupting the live stream.
    private var primaryActionIsStop: Bool {
        isGenerating && !hasInputText
    }

    @ViewBuilder
    private func primaryActionButton() -> some View {
        Button {
            if primaryActionIsStop {
                cancelCurrentGeneration()
            } else {
                sendMessage()
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

    @ViewBuilder
    private func inputField() -> some View {
        if #available(macOS 15.0, iOS 18.0, *) {
            TextArea(
                text: $inputText,
                placeholder: Text("Ask AI to draw...")
            )
            .keyDownHandler(
                TextFieldKeyDownEventHandler(triggers: [(36, nil)]) { event in
                    guard let event else { return nil }
                    if event.keyCode == 36, !event.modifierFlags.contains(.shift) {
                        sendMessage()
                        return nil           // 消费 plain enter
                    }
                    return event             // shift+enter 透传，系统自动插入 \n 并移动光标
                }
            )
            .background { style.background }
            .focused($isInputFocused)
        } else {
            TextEditor(text: $inputText)
                .frame(height: 160)
                .focused($isInputFocused)
        }
    }
    
    private func sendMessage() {
        let trimmedText = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else { return }

        // Client-side credits gate: if we already know the balance is empty,
        // skip the round-trip and open the paywall immediately. We only block
        // when the value is loaded — `creditsInfo == nil` means "not fetched
        // yet" and we let the request go through (server will reject and the
        // catch-side dispatcher still routes to the paywall).
        if let balance = llmState.creditsInfo?.balance, balance <= 0 {
            Store.shared.togglePaywall(reason: .aiInsufficientCredits)
            return
        }

        // Mid-stream: queue and clear the input so the user can keep typing
        // the next one. The drain runs when `currentTask` finishes.
        if isGenerating {
            withAnimation(.easeInOut(duration: 0.2)) {
                pendingQueue.append(PendingQueueMessage(text: trimmedText))
            }
            inputText = ""
            return
        }

        inputText = ""
        startSend(prompt: trimmedText)
    }

    /// Kicks off the actual network/stream pipeline for `prompt`. Stores the
    /// Task in `currentTask` so the stop button can cancel it; on completion
    /// (success or failure) it clears the slot and drains the queue.
    private func startSend(prompt: String) {
        let newConversationID = UUID().uuidString

        // Build the user message ahead of time so we can capture its id
        // for the AI chat session begin hook (anchors the `.aiPre`
        // checkpoint to this exact message — UI later renders a
        // "revert to here" affordance on the message row).
        let userMessage = ChatMessageContent(role: .user, content: prompt)
        let userMessageID = userMessage.id

        currentTask = Task {
            // Tracked so the trailing block can decide whether to write
            // `.aiPost` (success) or just clear suppression (failure /
            // cancel).
            var sessionOpened = false
            var streamSucceeded = false
            let conversationIDForSession: String = self.conversationID ?? newConversationID

            do {
                await MainActor.run {
                    ExcalidrawCoordinatorRegistry.shared.update(
                        normal: fileState.excalidrawWebCoordinator,
                        collaboration: fileState.excalidrawCollaborationWebCoordinator
                    )
                }
                let canvasTarget: ExcalidrawCoordinatorRegistry.CanvasTarget = {
                    switch fileState.currentActiveFile {
                        case .collaborationFile:
                            .collaboration
                        default:
                            .normal
                    }
                }()
                let selectedElementIDs: [String]? = await MainActor.run {
                    let coordinator: ExcalidrawCanvasView.Coordinator? = switch canvasTarget {
                        case .normal:
                            fileState.excalidrawWebCoordinator
                        case .collaboration:
                            fileState.excalidrawCollaborationWebCoordinator
                    }
                    let ids = coordinator?.selectedElementIDs ?? []
                    return ids.isEmpty ? nil : ids
                }
                let context = try await ExcalidrawChatInvocationContext(
                    currentFileData: currentFileData,
                    canvasTarget: canvasTarget,
                    selectedElementIDs: selectedElementIDs
                )

                // Make sure agent config is loaded so `activeModel` resolves to the
                // server-blessed default (or the user's picker selection) rather
                // than the hard-coded fallback.
                await loadAgentConfigIfNeeded()
                let model = await MainActor.run { activeModel }

                // Open the AI chat session: snapshots the current active
                // file as `.aiPre` (anchored to this user message) and
                // flips suppression on so all canvas mutations during
                // the round don't write to user history.
                try await fileState.beginAIChatSession(
                    conversationID: conversationIDForSession,
                    userMessageID: userMessageID
                )
                sessionOpened = true

                if self.conversation == nil {
                    self.conversationID = newConversationID
                    // Promote the staged pick (if any) to a per-conversation
                    // override now that we have an id. Without this, the
                    // user's pre-send model choice would be lost on reopen
                    // — `pendingModelSelection` is @State, conversation
                    // overrides survive the view's lifetime.
                    if let pending = await MainActor.run(body: { pendingModelSelection }) {
                        await MainActor.run {
                            prefs.setModel(pending, for: newConversationID)
                            pendingModelSelection = nil
                        }
                    }
                    try await llmState.createConversation(
                        id: newConversationID,
                        type: .regular,
                        model: model,
                        // Tool roster + agentID centralized in
                        // `ExcalidrawAgentConfig` so the persistence
                        // restore path uses the exact same wiring.
                        agentConfig: ExcalidrawAgentConfig.defaultConfig(),
                        messages: [.content(userMessage)],
                        context: context
                    )
                } else {
                    try await llmState.sendMessage(
                        to: self.conversationID!,
                        model: model,
                        message: .content(userMessage),
                        context: context
                    )
                }

                // Stream completed without throwing. The `.aiPost`
                // snapshot will anchor to whatever the trailing assistant
                // message id ends up being — read after-the-fact rather
                // than guessing.
                streamSucceeded = true
            } catch {
                // Single-funnel through `presentAIChatError` so intent-based
                // dispatch (credits / auth / rate-limit / forbidden / generic)
                // lives in one place. CancellationError is swallowed inside
                // the helper.
                await MainActor.run {
                    alertToast.presentAIChatError(error)
                }
            }

            // Close the session unconditionally — on success writes
            // `.aiPost` snapshot anchored to the trailing assistant
            // message; on failure / cancel just clears the suppression
            // flag (no post snapshot).
            if sessionOpened {
                let assistantMessageID: String? = await MainActor.run {
                    guard streamSucceeded else { return nil }
                    let convo = llmState.conversations.value?
                        .first(where: { $0.id == conversationIDForSession })
                    return convo?.messages.last(where: {
                        if case .content(let c) = $0, c.role == .assistant {
                            return true
                        }
                        return false
                    })?.id
                }
                // `description` is intentionally nil for now — wired up
                // later (likely from `final_answer` tool args).
                await fileState.endAIChatSession(
                    success: streamSucceeded,
                    assistantMessageID: assistantMessageID,
                    description: nil
                )
            }

            await MainActor.run {
                currentTask = nil
                drainQueueIfNeeded()
            }
        }
    }

    /// Stop button: ask LLMKit to terminate the in-flight generation
    /// (closes the SSE stream + cleans up streamingStore + commits/rolls back
    /// partial state per LLMKit's policy). Then locally cancel our send Task
    /// so its `await` chain unwinds quickly, and drop any queued follow-ups
    /// — "stop" is the user's intent to halt, not "stop this one but send
    /// the next".
    private func cancelCurrentGeneration() {
        if let id = conversationID {
            llmState.cancelGeneration(conversationID: id)
        }
        currentTask?.cancel()
        withAnimation(.easeInOut(duration: 0.2)) {
            pendingQueue.removeAll()
        }
    }

    /// Pop the next queued message and start a fresh send. Called from the
    /// completion path of `startSend` so messages flow strictly serially.
    private func drainQueueIfNeeded() {
        guard !pendingQueue.isEmpty else { return }
        let next: PendingQueueMessage = withAnimation(.easeInOut(duration: 0.2)) {
            pendingQueue.removeFirst()
        }
        startSend(prompt: next.text)
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
