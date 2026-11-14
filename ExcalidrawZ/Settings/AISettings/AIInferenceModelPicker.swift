import SwiftUI
import LLMCore
import ChocofordUI

@MainActor
struct AIInferenceModelPicker: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var billing: AIInferenceBillingState
    @Bindable var catalog: AIInferenceModelCatalog
    let selectedID: String
    var connectionID: String? = nil
    var integrationMode: AIInferenceIntegrationMode? = nil
    let onSelect: (String) async throws -> Void

    @State private var search = ""
    @State private var manualID = ""
    @State private var isManualEntryExpanded = false
    @State private var selectionError: String?
    @State private var isSelecting = false

    private var profile: AIInferenceConnectionProfile? {
        billing.profiles.first { $0.id == (connectionID ?? billing.selectedProfileID) }
    }

    private var snapshot: AIInferenceModelCatalog.Snapshot { catalog.snapshot(for: billing, profileID: connectionID, integrationMode: integrationMode) }

    private var models: [LLMBYOKModel] {
        var models = snapshot.models
        let known = Set(models.map(\.id))
        let saved = Set(billing.savedModelIDs(profileID: connectionID ?? billing.selectedProfileID) + [selectedID]).filter { !$0.isEmpty && !known.contains($0) }
        models += saved.sorted().map { LLMBYOKModel(id: $0) }
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return models.filter {
            query.isEmpty || $0.id.localizedCaseInsensitiveContains(query)
                || $0.displayName.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 12)

            if let error = snapshot.errorMessage {
                errorLabel(error)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 8)
            }

            modelList

            manualEntry
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 20)
        }
#if os(macOS)
        .frame(width: 520, height: 600)
#endif
        .task(id: billing.modelCatalogRevision) {
            await catalog.load(for: billing, profileID: connectionID, integrationMode: integrationMode)
        }
        .allowsHitTesting(!isSelecting)
        .onAppear {
            manualID = selectedID
            isManualEntryExpanded = profile?.configuration?.modelDiscovery == nil
        }
    }

    @ViewBuilder
    private var header: some View {
        if #available(macOS 26.0, iOS 26.0, *) {
            GlassEffectContainer(spacing: 8) {
                headerContent
            }
        } else {
            headerContent
        }
    }

    private var headerContent: some View {
        VStack(spacing: 16) {
            ZStack {
                VStack(spacing: 3) {
                    Text(.localizable(.aiBYOKModelPickerTitle))
                        .font(.title3.weight(.semibold))
                    if let profile {
                        Text(profile.displayName)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .lineLimit(1)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 52)
                .frame(maxWidth: .infinity)

                HStack {
                    Button { dismiss() } label: {
                        Label(.localizable(.generalButtonDone), systemImage: "xmark")
                            .labelStyle(.iconOnly)
                            .frame(width: 18, height: 18)
                    }
                    .modernButtonStyle(style: .glass, size: .large, shape: .circle)
                    .keyboardShortcut(.cancelAction)

                    Spacer(minLength: 12)

                    Button {
                        Task { await catalog.load(for: billing, profileID: connectionID, integrationMode: integrationMode, force: true) }
                    } label: {
                        ZStack {
                            Label(.localizable(.aiBYOKRefreshModels), systemImage: "arrow.clockwise")
                                .labelStyle(.iconOnly)
                                .opacity(snapshot.isLoading ? 0 : 1)
                            if snapshot.isLoading { ProgressView().controlSize(.small) }
                        }
                        .frame(width: 18, height: 18)
                    }
                    .modernButtonStyle(style: .glass, size: .large, shape: .circle)
                    .help(.localizable(.aiBYOKRefreshModels))
                    .disabled(snapshot.isLoading || profile?.configuration?.modelDiscovery == nil)
                }
            }
            searchField
        }
    }

    @ViewBuilder
    private var searchField: some View {
        if #available(macOS 26.0, iOS 26.0, *) {
            searchFieldContent
                .glassEffect(.regular, in: .capsule)
        } else {
            searchFieldContent
                .background(.regularMaterial, in: Capsule())
        }
    }

    private var searchFieldContent: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField(.localizable(.aiBYOKSearchModels), text: $search)
                .textFieldStyle(.plain)
                .labelsHidden()
#if os(iOS)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
#endif
            if !search.isEmpty {
                Button { search = "" } label: {
                    Label(.localizable(.aiBYOKClearSearch), systemImage: "xmark.circle.fill")
                        .labelStyle(.iconOnly)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 38)
    }

    @ViewBuilder
    private var modelList: some View {
        if models.isEmpty {
            VStack(spacing: 12) {
                if snapshot.isLoading {
                    ProgressView()
                    Text(.localizable(.aiBYOKLoadingModels))
                } else {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 28, weight: .light))
                    Text(.localizable(profile == nil ? .aiBYOKSelectConnection
                        : profile?.configuration?.modelDiscovery == nil ? .aiBYOKModelListDisabled
                        : search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            ? .aiBYOKNoModels : .aiBYOKNoSearchResults))
                }
            }
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(20)
        } else {
            ScrollView {
                LazyVStack(spacing: 4) {
                    ForEach(models) { model in
                        AIInferenceModelPickerRow(model: model, isSelected: model.id == selectedID) {
                            select(model.id)
                        }
                        .disabled(billing.isBusy)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
            }
            .frame(maxHeight: .infinity)
        }
    }

    private var manualEntry: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation(.easeInOut(duration: 0.18)) {
                    isManualEntryExpanded.toggle()
                    selectionError = nil
                }
            } label: {
                Label(.localizable(.aiBYOKCustomModel), systemImage: isManualEntryExpanded ? "minus.circle" : "plus.circle")
                    .font(.callout)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.accentColor)

            if isManualEntryExpanded {
                HStack(spacing: 10) {
                    TextField(.localizable(.aiBYOKModelID), text: $manualID)
                        .textFieldStyle(.plain)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
#if os(iOS)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
#endif
                        .onSubmit { select(manualID) }
                    Button(.localizable(.aiBYOKUseModel)) { select(manualID) }
                        .modernButtonStyle(style: .glassProminent, size: .regular, shape: .modern)
                        .disabled(billing.isBusy || (try? billing.modelForChat(overridingModelID: manualID, profileID: connectionID)) == nil)
                }
            }
            if let selectionError { errorLabel(selectionError) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func errorLabel(_ message: String) -> some View {
        Label(message, systemImage: "exclamationmark.circle")
            .font(.footnote)
            .foregroundStyle(.red)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func select(_ id: String) {
        guard !isSelecting else { return }
        isSelecting = true
        Task { @MainActor in
            defer { isSelecting = false }
            do {
                guard !billing.isBusy else { throw AIInferenceBillingError.settingsBusy }
                _ = try billing.modelForChat(overridingModelID: id, profileID: connectionID)
                try await onSelect(id)
                dismiss()
            } catch {
                selectionError = (AIInferenceErrorMessage.localizedError(for: error) ?? error).localizedDescription
            }
        }
    }

}

private struct AIInferenceModelPickerRow: View {
    let model: LLMBYOKModel
    let isSelected: Bool
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(model.displayName)
                        .font(.body.weight(isSelected ? .semibold : .regular))
                        .lineLimit(1)
                    if model.displayName != model.id {
                        Text(model.id)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                Spacer(minLength: 0)
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(Color.accentColor)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
            .background(isSelected ? Color.accentColor.opacity(0.10)
                        : Color.primary.opacity(isHovered ? 0.04 : 0), in: RoundedRectangle(cornerRadius: 12))
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help(model.id)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}
