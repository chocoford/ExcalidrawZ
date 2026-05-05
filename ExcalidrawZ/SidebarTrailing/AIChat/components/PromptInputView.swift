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

struct PromptInputView: View {
    @EnvironmentObject private var llmState: LLMStateObject
    @EnvironmentObject private var fileState: FileState
    @Environment(\.alertToast) private var alertToast

    @Binding var conversationID: String?
    
    init(conversationID: Binding<String?>) {
        self._conversationID = conversationID
    }

    
    @State private var inputText: String = ""
    @State private var agentConfig: DomainAgentConfigResponse?
    @State private var selectedModel: SupportedModel?

    /// In-flight send task. While non-nil, the assistant is generating a reply.
    /// Cancelling this task propagates Swift cooperative cancellation through
    /// `llmState.sendMessage`'s stream consumer, which terminates the request.
    @State private var currentTask: Task<Void, Never>?

    /// Messages typed while an earlier reply was still streaming. Drained
    /// (FIFO) once the current stream finishes.
    @State private var pendingQueue: [String] = []

    @FocusState private var isInputFocused: Bool

    /// Server-side agent identifier; the backend resolves system prompt + agent
    /// config from this. Tools list still ships from the client because tool
    /// implementations are local.
    private let agentID = "excalidraw-canvas"

    /// Resolved model used for the next request. Falls back to the agent's
    /// default, then a hard-coded floor if the config hasn't loaded yet.
    private var activeModel: SupportedModel {
        selectedModel ?? agentConfig?.defaultModel ?? .claudeSonnet4_6
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
                    selectedModel = model
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
    
    @ViewBuilder
    private func content() -> some View {
        VStack(spacing: 6) {
            // Negative spacing tucks the banner's bottom behind the input
            // box; SwiftUI's default sibling z-order draws later children on
            // top, so the input field's opaque background covers the banner's
            // bottom rounded edge → the "peeking out from behind" look.
            VStack(spacing: -18) {
                lowCreditsBanner()
                    .padding(.horizontal, 10)
                    .animation(
                        .easeInOut(duration: 0.25),
                        value: shouldShowLowCreditsBanner
                    )

                ZStack {
                    if #available(macOS 26.0, iOS 26.0, *) {
                        inputField()
                            .background {
                                RoundedRectangle(cornerRadius: 20)
                                    .fill(Color.textBackgroundColor)
                                    .glassEffect(in: RoundedRectangle(cornerRadius: 20))
                            }
                    } else {
                        inputField()
                            .background {
                                RoundedRectangle(cornerRadius: 20)
                                    .fill(.regularMaterial)
                            }
                    }
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(.separator, lineWidth: 0.5)
                }
                .shadow(color: .black.opacity(0.2), radius: 4)
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
                    .contentTransition(.symbolEffect(.replace))
            } else {
                Image(systemSymbol: primaryActionIsStop ? .stopFill : .arrowUp)
            }
        }
        .modernButtonStyle(style: .glass, shape: .circle)
        // Stop is always enabled while generating. Send needs text.
        .disabled(!primaryActionIsStop && !hasInputText)
    }
    
    /// Threshold for showing the low-credits hint above the input box.
    /// Tuned conservatively — at 100 credits a few exchanges still fit, so
    /// the user has time to act on the warning before hitting `.insufficientCredits`.
    private static let lowCreditsThreshold: Double = 100

    private var shouldShowLowCreditsBanner: Bool {
        guard let balance = llmState.creditsInfo?.balance else { return false }
        return balance < Self.lowCreditsThreshold
    }

    @ViewBuilder
    private func lowCreditsBanner() -> some View {
        if shouldShowLowCreditsBanner,
           let balance = llmState.creditsInfo?.balance {
            Button {
                Store.shared.togglePaywall(reason: .aiInsufficientCredits)
            } label: {
                HStack(spacing: 6) {
                    Image(systemSymbol: .exclamationmarkTriangleFill)
                        .foregroundStyle(.orange)
                    Text("Only \(Int(balance)) credits left — tap to top up")
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                    
                    Image(systemSymbol: .arrowRight)
                }
                .font(.caption)
                .padding(.horizontal, 14)
                .padding(.top, 6)
                // Extra bottom padding extends the background under the input
                // box; combined with the parent VStack's negative spacing this
                // produces the "peeking out from behind the input" effect.
                .padding(.bottom, 24)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background {
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color.orange.opacity(0.15))
                }
                .contentShape(RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(.plain)
            .transition(.opacity.combined(with: .move(edge: .bottom)))
        }
    }

    @ViewBuilder
    private func inputField() -> some View {
        if #available(macOS 15.0, iOS 18.0, *) {
            AutoGrowTextEditor(
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

        // Mid-stream: queue and clear the input so the user can keep typing
        // the next one. The drain runs when `currentTask` finishes.
        if isGenerating {
            pendingQueue.append(trimmedText)
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

        currentTask = Task {
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

                if self.conversation == nil {
                    self.conversationID = newConversationID
                    try await llmState.createConversation(
                        id: newConversationID,
                        type: .custom("File"),
                        model: model,
                        agentConfig: .withTools(
                            ["web_search", "web_fetch", "read_file", "read_canvas_image", "calculator", "datetime", "adjust_elements", "final_answer"],
                            agentID: agentID
                        ),
                        messages: [.content(.init(role: .user, content: prompt))],
                        context: context
                    )
                } else {
                    try await llmState.sendMessage(
                        to: self.conversationID!,
                        model: model,
                        message: .content(.init(role: .user, content: prompt)),
                        context: context
                    )
                }
            } catch {
                // Single-funnel through `presentAIChatError` so intent-based
                // dispatch (credits / auth / rate-limit / forbidden / generic)
                // lives in one place. CancellationError is swallowed inside
                // the helper.
                await MainActor.run {
                    alertToast(error)
                }
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
        pendingQueue.removeAll()
    }

    /// Pop the next queued message and start a fresh send. Called from the
    /// completion path of `startSend` so messages flow strictly serially.
    private func drainQueueIfNeeded() {
        guard !pendingQueue.isEmpty else { return }
        let next = pendingQueue.removeFirst()
        startSend(prompt: next)
    }
}
