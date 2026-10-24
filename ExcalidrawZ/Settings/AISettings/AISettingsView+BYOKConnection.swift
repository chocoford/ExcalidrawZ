import SwiftUI
import LLMCore
import LLMKit
import ChocofordUI

enum AIInferenceConnectionSheet: Identifiable {
    case add
    case edit(String)

    var id: String {
        switch self {
            case .add: "add"
            case .edit(let id): id
        }
    }

    var profileID: String? {
        if case .edit(let id) = self { id } else { nil }
    }
}

@MainActor
struct AIInferenceConnectionEditor: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var billing: AIInferenceBillingState
    let profileID: String?

    @State private var provider: AIInferenceConnection = .openAI
    @State private var name = ""
    @State private var baseURL = ""
    @State private var key = ""
    @State private var keyEndpoint = ""
    @State private var discoveryEnabled = true
    @State private var discoveryPath = ""
    @State private var statusMessage: String?
    @State private var isSaving = false
    @State private var saveTask: Task<Void, Never>?
    @State private var isConfirmingRemoval = false
    @State private var didLoad = false

    private var isNewConnection: Bool { profileID == nil }
    private var profile: AIInferenceConnectionProfile? {
        billing.profiles.first { $0.id == profileID }
    }
    private var preset: LLMBYOKConfiguration? { provider.presetConfiguration }
    private var showsCustomURL: Bool {
        guard let preset else { return true }
        // Keep existing endpoint overrides visible when editing older connections.
        guard let savedURL = profile?.configuration?.baseURL else { return false }
        return savedURL != preset.baseURL
    }
    private var effectiveURL: String {
        let address = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        return address.isEmpty ? preset?.baseURL.absoluteString ?? "" : address
    }
    private var hasModelDiscovery: Bool {
        provider == .custom ? discoveryEnabled : (profile?.configuration ?? preset)?.modelDiscovery != nil
    }
    private var canSave: Bool {
        !billing.isBusy && !isSaving && (try? makeConfiguration()) != nil
            && (try? AIInferenceBillingState.validatedKey(key)) != nil
    }

    var body: some View {
        VStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 16) {
                Text(.localizable(isNewConnection ? .aiBYOKAddConnection : .aiBYOKEditConnection))
                    .font(.headline)

                connectionFields

                if provider == .custom { modelDiscoveryFields }

                if !hasModelDiscovery {
                    Text(.localizable(.aiBYOKManualConnectionHelp))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Text(.localizable(.aiBYOKSettingsFooter))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if let statusMessage {
                    Text(statusMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .disabled(billing.isBusy || isSaving)

            actionBar
        }
        .padding(20)
        .textFieldStyle(.plain)
        .confirmationDialog(String(localizable: .aiBYOKRemoveConnection), isPresented: $isConfirmingRemoval) {
            Button(.localizable(.aiBYOKRemoveConnection), role: .destructive) {
                guard let profileID else { return }
                do {
                    try billing.removeConnection(profileID)
                    dismiss()
                } catch { showError(error) }
            }
        }
#if os(macOS)
        .frame(width: 520)
        .fixedSize(horizontal: false, vertical: true)
#endif
        .interactiveDismissDisabled(isSaving)
        .onAppear(perform: load)
        .onDisappear {
            saveTask?.cancel()
            key = ""
        }
    }

    private var connectionFields: some View {
        VStack(spacing: 0) {
            if isNewConnection {
                fieldRow(.aiBYOKProvider) {
                    Picker(.localizable(.aiBYOKProvider), selection: Binding(
                        get: { provider }, set: { selectProvider($0) }
                    )) {
                        ForEach(AIInferenceConnection.allCases) { provider in
                            Text(provider.title).tag(provider)
                        }
                    }
                    .pickerStyle(.menu)
                    .fixedSize()
                }
                rowDivider
            }
            fieldRow(.aiBYOKConnectionName) {
                TextField(.localizable(.aiBYOKConnectionName), text: $name, prompt: Text(provider.title))
            }
            if showsCustomURL {
                rowDivider
                fieldRow(.aiBYOKBaseURL) {
                    TextField(.localizable(.aiBYOKBaseURL), text: Binding(
                        get: { baseURL }, set: { updateBaseURL($0) }
                    ), prompt: Text(preset?.baseURL.absoluteString ?? "https://api.example.com/v1/"))
#if os(iOS)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
#endif
                }
            }
            rowDivider
            fieldRow(.aiBYOKKeyPlaceholder) {
                SecureField(.localizable(.aiBYOKKeyPlaceholder), text: Binding(
                    get: { key }, set: {
                        key = $0
                        keyEndpoint = effectiveURL
                        statusMessage = nil
                    }
                ), prompt: Text(.localizable(.aiBYOKRequiredKey)))
#if os(iOS)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
#endif
            }
        }
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
    }

    private var modelDiscoveryFields: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(.localizable(.aiBYOKModelDiscovery))
                .font(.subheadline)
                .foregroundStyle(.secondary)
            VStack(spacing: 0) {
                if !isNewConnection {
                    fieldRow(.aiBYOKModelDiscoveryEnabled) {
                        Toggle(.localizable(.aiBYOKModelDiscoveryEnabled), isOn: $discoveryEnabled)
                            .toggleStyle(.switch)
                            .fixedSize()
                    }
                    if discoveryEnabled { rowDivider }
                }
                if discoveryEnabled {
                    fieldRow(.aiBYOKModelDiscoveryPath) {
                        TextField(.localizable(.aiBYOKModelDiscoveryPath), text: $discoveryPath, prompt: Text("models"))
#if os(iOS)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
#endif
                    }
                }
            }
            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
            Text(.localizable(.aiBYOKCustomEndpointHelp))
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func fieldRow<Content: View>(
        _ title: String.Localizable,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(alignment: .center, spacing: 16) {
            Text(.localizable(title))
                .layoutPriority(1)
            content()
                .labelsHidden()
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .frame(minHeight: 36)
        .padding(.horizontal, 12)
        .padding(.vertical, 2)
    }

    private var rowDivider: some View {
        Divider().padding(.horizontal, 12)
    }

    @ViewBuilder
    private var actionBar: some View {
        if #available(macOS 26.0, iOS 26.0, *) {
            GlassEffectContainer(spacing: 8) {
                actionBarContent
            }
        } else {
            actionBarContent
        }
    }

    private var actionBarContent: some View {
        HStack(spacing: 8) {
            if !isNewConnection {
                Button(.localizable(.aiBYOKRemoveConnection), role: .destructive) {
                    isConfirmingRemoval = true
                }
                .modernButtonStyle(style: .glass, size: .regular, shape: .modern)
                .tint(.red)
                .disabled(billing.isBusy || isSaving)
            }
            Spacer(minLength: 12)
            if isSaving { ProgressView().controlSize(.small) }
            Button(.localizable(.generalButtonCancel)) {
                saveTask?.cancel()
                dismiss()
            }
            .keyboardShortcut(.cancelAction)
            .modernButtonStyle(style: .glass, size: .regular, shape: .modern)
            Button(.localizable(.generalButtonSave), action: saveConnection)
                .modernButtonStyle(style: .glassProminent, size: .regular, shape: .modern)
                .keyboardShortcut(.defaultAction)
                .disabled(!canSave)
        }
    }

    private func selectProvider(_ provider: AIInferenceConnection) {
        self.provider = provider
        baseURL = ""
        key = ""
        keyEndpoint = effectiveURL
        discoveryEnabled = true
        discoveryPath = ""
        statusMessage = nil
    }

    private func updateBaseURL(_ value: String) {
        baseURL = value
        if effectiveURL != keyEndpoint {
            key = ""
            keyEndpoint = effectiveURL
        }
        statusMessage = nil
    }

    private func load() {
        guard !didLoad else { return }
        didLoad = true
        guard let profile else {
            keyEndpoint = effectiveURL
            return
        }
        provider = profile.provider
        name = profile.name
        let configuration = profile.configuration
        baseURL = configuration?.baseURL == preset?.baseURL ? "" : configuration?.baseURL.absoluteString ?? ""
        keyEndpoint = effectiveURL
        discoveryEnabled = configuration.map { $0.modelDiscovery != nil } ?? true
        discoveryPath = configuration?.modelDiscovery?.path == "models" ? "" : configuration?.modelDiscovery?.path ?? ""
        do { key = try billing.keyForEditing(profileID: profileID) }
        catch { showError(error) }
    }

    private func makeConfiguration() throws -> LLMBYOKConfiguration {
        guard let url = URL(string: effectiveURL) else { throw AIInferenceBillingError.invalidConfiguration }
        var configuration = profile?.configuration ?? preset ?? LLMBYOKConfiguration(baseURL: url)
        configuration.baseURL = url
        configuration.defaultModel = nil
        configuration.options.auxiliaryModel = nil
        if provider == .custom {
            let path = discoveryPath.trimmingCharacters(in: .whitespacesAndNewlines)
            configuration.modelDiscovery = discoveryEnabled ? .init(path: path.isEmpty ? "models" : path) : nil
        }
        try configuration.validate()
        return configuration
    }

    private func saveConnection() {
        guard canSave else { return }
        do {
            let configuration = try makeConfiguration()
            let key = try AIInferenceBillingState.validatedKey(key)
            let connectionProvider = LLMBYOKProvider(configuration: configuration, apiKeyProvider: { key })
            let provider = provider
            let name = name
            statusMessage = nil
            isSaving = true
            saveTask = Task { @MainActor in
                defer { isSaving = false; saveTask = nil }
                do {
                    if configuration.modelDiscovery != nil {
                        _ = try await LLMClient.shared.listBYOKModels(provider: connectionProvider)
                    }
                    try Task.checkCancellation()
                    if let profileID {
                        try billing.updateConnection(profileID, name: name, configuration: configuration, apiKey: key)
                    } else {
                        try billing.addConnection(provider, name: name, configuration: configuration, apiKey: key)
                    }
                    dismiss()
                } catch {
                    guard !Task.isCancelled else { return }
                    showError(error)
                }
            }
        } catch { showError(error) }
    }

    private func showError(_ error: Error) {
        statusMessage = (AIInferenceErrorMessage.localizedError(for: error) ?? error).localizedDescription
    }
}
