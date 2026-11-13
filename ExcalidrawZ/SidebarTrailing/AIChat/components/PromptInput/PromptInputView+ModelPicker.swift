// Model menus and explicit conversation-route changes share the same captured selection.
import SwiftUI
import ChocofordUI
import SwiftyAlert
import LLMKit
import LLMCore
import SFSafeSymbols

extension PromptInputView {
    @ViewBuilder
    var modelPicker: some View {
        let _ = AIChatRenderDebug.hit("PromptInputView.modelPicker")

        SwiftUI.Group {
            if modelPickerUsesDirectSheet {
                Button {
                    openBYOKModelPicker()
                } label: {
                    modelPickerLabel
                }
                .buttonStyle(.plain)
            } else {
                Menu {
                    modelProfilePickerButtons()
                } label: {
                    modelPickerLabel
                }
            }
        }
        .menuIndicator(.hidden)
        .modifier(PromptActionBarHoverEffect())
        .help(modelPickerTitle)
        .disabled(isGenerating || isCompactingContext || isUpdatingConversationRoute || inferenceBilling.isBusy)
    }

    private var modelPickerLabel: some View {
        Text(modelPickerTitle)
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .truncationMode(.middle)
            .frame(height: actionBarIconFrameLength)
            .contentShape(Rectangle())
    }

    @MainActor
    var modelPickerTitle: String {
        guard let route = try? routeForSend() else { return String(localizable: .aiBYOKSelectModel) }
        if let id = route.byokModelID {
            return byokModelCatalog.displayName(for: id, billing: inferenceBilling, profileID: modelPickerConnectionID, integrationMode: modelPickerIntegrationMode)
        }
        if route == .legacy, modelPickerUsesBYOK { return activeModelSelection?.model.rawValue ?? String(localizable: .aiBYOKSelectModel) }
        if let profileID = route.profileID {
            return schemeCatalog.options.first { $0.profileID == profileID }?.title
                ?? String(localizable: .aISchemeChooseProfile)
        }
        if let conversationID, let selection = routing.legacySelections[conversationID] {
            return selection.model.displayName
        }
        return String(localizable: .aISchemeLegacyConversation)
    }

    @MainActor
    @ViewBuilder
    func modelProfilePickerButtons() -> some View {
        if conversation?.schemeConnection != nil {
            if modelPickerUsesBYOK {
                Button(.localizable(.aiBYOKModelPickerTitle)) { openBYOKModelPicker() }
                Menu(.localizable(.aiBYOKConnectionsTitle)) { byokConnectionMenuButtons() }
                Divider()
                Menu(.localizable(.aiServiceExcalidrawZ)) { platformProfileButtons() }
            } else {
                platformProfileButtons()
                Divider()
                Menu(.localizable(.aISchemeOptimizedBYOK)) { byokConnectionMenuButtons() }
            }
        } else if modelPickerUsesBYOK {
            Button(.localizable(.aiBYOKModelPickerTitle)) { openBYOKModelPicker() }
        } else if let conversation, conversation.schemeConnection == nil, conversation.directConnection == nil {
            Text(.localizable(.aISchemeLegacyConversation))
            Button(.localizable(.aISchemeNewConversation)) {
                aiChatState.finishEditing()
                conversationID = nil
                pendingProfileID = nil
            }
        } else {
            platformProfileButtons()
        }
        if !modelPickerUsesDirectSheet, let error = schemeCatalog.errorMessage {
            Text(error)
        }
    }

    @MainActor
    @ViewBuilder
    private func platformProfileButtons() -> some View {
        if availableModelOptions.isEmpty, schemeCatalog.errorMessage == nil {
            Text(.localizable(schemeCatalog.isLoading ? .aISchemeLoadingProfiles : .aISchemeNoProfiles))
        }
        ForEach(availableModelOptions) { option in
            Button {
                let selectedConversationID = conversationID
                let selectedDraftKey = promptDraftKey
                let previousRoute = try? routeForSend()
                Task {
                    do {
                        guard conversationID == selectedConversationID, promptDraftKey == selectedDraftKey,
                              (try? routeForSend()) == previousRoute else { throw AIInferenceBillingError.selectionChanged }
                        try await pickProfile(option)
                    }
                    catch { alertToast.presentAIChatError(error) }
                }
            } label: {
                if option.profileID == (try? routeForSend())?.profileID {
                    Label(option.title, systemSymbol: .checkmark)
                } else { Text(option.title) }
            }
            .disabled(!canSelectModelOption(option) || schemeCatalog.isLoading)
        }
    }

    @MainActor
    @ViewBuilder
    private func byokConnectionMenuButtons() -> some View {
        if inferenceBilling.profiles.isEmpty { Text(.localizable(.aiBYOKSelectConnection)) }
        ForEach(inferenceBilling.profiles) { profile in
            Button { openBYOKModelPicker(connectionID: profile.id) } label: {
                if modelPickerConnectionID == profile.id {
                    Label(profile.displayName, systemSymbol: .checkmark)
                } else { Text(profile.displayName) }
            }
        }
    }

    @MainActor
    func openBYOKModelPicker(connectionID: String? = nil) {
        do {
            guard !isGenerating, !isCompactingContext, !inferenceBilling.isBusy, !isUpdatingConversationRoute else {
                throw LLMSchemeStateError.generationInProgress
            }
            let route = try? routeForSend()
            if conversationID != nil, route == nil { throw AIChatRoutingError.invalidRoute }
            guard AIServiceConsentState.shared.hasAccepted(.byok) else { throw AIChatRoutingError.consentRequired }
            guard let id = connectionID ?? modelPickerConnectionID ?? inferenceBilling.selectedProfileID,
                  let profile = inferenceBilling.profiles.first(where: { $0.id == id }) else {
                throw AIInferenceBillingError.missingConnection
            }
            // A Scheme conversation always uses Optimized discovery, regardless of defaults.
            let mode: AIInferenceIntegrationMode = conversation?.schemeConnection != nil
                ? .optimized : modelPickerIntegrationMode ?? inferenceBilling.integrationMode
            guard mode != .optimized || store.canUseOptimizedBYOKServices else {
                store.togglePaywall(reason: .optimizedBYOK)
                return
            }
            byokModelPickerTarget = .init(conversationID: conversationID, draftKey: promptDraftKey,
                expectedRoute: route, connectionID: id, integrationMode: mode,
                selectedModelID: modelPickerConnectionID == id ? route?.byokModelID ?? profile.lastModelID ?? ""
                    : profile.lastModelID ?? "", billingRevision: inferenceBilling.modelCatalogRevision)
        } catch { alertToast.presentAIChatError(error) }
    }

    @MainActor
    func pickBYOKModel(_ id: String, target: AIChatBYOKPickerTarget) async throws {
        guard !isGenerating, !isCompactingContext, !isUpdatingConversationRoute else {
            throw LLMSchemeStateError.generationInProgress
        }
        guard conversationID == target.conversationID, promptDraftKey == target.draftKey,
              (try? routeForSend()) == target.expectedRoute else { throw AIInferenceBillingError.selectionChanged }
        if let conversation, conversation.directConnection != nil {
            let model = try inferenceBilling.modelForRoute(connectionID: target.connectionID, modelID: id)
            try await AIChatInferenceSessions.shared.updateDirectModel(model, in: conversation, state: llmState)
        } else if let conversation, let binding = conversation.schemeConnection {
            let model = try inferenceBilling.modelForRoute(connectionID: target.connectionID, modelID: id)
            try await routing.select(.optimizedBYOK(schemeID: binding.selection.schemeID,
                connectionID: target.connectionID, modelID: model.rawValue), for: conversation.id, state: llmState)
        } else {
            try inferenceBilling.validateSelection(expectedRevision: target.billingRevision)
            guard target.connectionID == inferenceBilling.selectedProfileID,
                  target.integrationMode == inferenceBilling.integrationMode else { throw AIInferenceBillingError.selectionChanged }
            let model = try inferenceBilling.modelForChat(overridingModelID: id, profileID: target.connectionID)
            try inferenceBilling.setModel(model.rawValue, for: conversationID)
        }
    }

    @MainActor
    func pickProfile(_ option: ExcalidrawModelProfileOption) async throws {
        guard !isGenerating, !isCompactingContext, !isUpdatingConversationRoute else {
            throw LLMSchemeStateError.generationInProgress
        }
        guard canSelectModelOption(option) else { return }
        let route = AIChatConversationRoute.platformScheme(
            schemeID: AIChatSchemeCatalog.schemeID, profileID: option.profileID
        )
        if let conversationID {
            try await routing.select(route, for: conversationID, state: llmState)
        } else {
            pendingProfileID = option.profileID
        }
    }

    func loadSchemeIfNeeded() async {
        if AIChatInferenceSessions.shared.session(for: conversationID).client.isDirectBYOK { return }
        if conversation?.directConnection != nil { return }
        if AIChatAvailability.usesDirectInference, conversation?.schemeConnection == nil { return }
        await schemeCatalog.refresh(forServerConversation: conversation?.schemeConnection != nil)
    }
}
