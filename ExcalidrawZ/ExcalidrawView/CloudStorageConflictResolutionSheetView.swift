//
//  CloudStorageConflictResolutionSheetView.swift
//  ExcalidrawZ
//

import SwiftUI

import ChocofordUI

struct CloudStorageConflictResolutionSheetView: View {
    @Environment(\.alertToast) private var alertToast
    @Environment(\.containerHorizontalSizeClass) private var containerHorizontalSizeClass
    @Environment(\.dismiss) private var dismiss

    let reference: CloudStorageDocumentReference
    let onCancel: (() -> Void)?

    @State private var preparedSnapshot: PreparedSnapshot?
    @State private var selectedVersion: CloudStorageConflictVersion?
    @State private var isLoading = true
    @State private var isResolving = false
    @State private var loadingError: Error?

    private let documentStore = CloudStorageDocumentStore.shared

    init(
        reference: CloudStorageDocumentReference,
        onCancel: (() -> Void)? = nil
    ) {
        self.reference = reference
        self.onCancel = onCancel
    }

    private struct PreparedSnapshot {
        let snapshot: CloudStorageConflictSnapshot
        let localFile: ExcalidrawFile
        let remoteFile: ExcalidrawFile
    }

    private var isCompact: Bool {
        containerHorizontalSizeClass == .compact
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            ZStack {
                if isLoading {
                    loadingView
                } else if let loadingError {
                    errorView(loadingError)
                } else if let preparedSnapshot {
                    versionSelection(preparedSnapshot)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            actions
        }
        .frame(
            minWidth: isCompact ? nil : 720,
            idealWidth: isCompact ? nil : 820,
            minHeight: isCompact ? nil : 560,
            idealHeight: isCompact ? nil : 620
        )
        .task(id: reference.id) {
            await loadVersions()
        }
        .interactiveDismissDisabled()
    }

    private var header: some View {
        HStack(spacing: 12) {
            Button {
                cancelResolution()
            } label: {
                Image(systemSymbol: .xmark)
            }
            .modernButtonStyle(style: .glass, size: .large, shape: .circle)

            VStack(alignment: .leading, spacing: 2) {
                Text(
                    String(
                        localized: "cloudStorageConflictResolutionTitle",
                        defaultValue: "Choose a Version"
                    )
                )
                .font(.headline)

                Text(documentStore.displayName(for: reference))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            Image(systemSymbol: .exclamationmarkTriangleFill)
                .foregroundStyle(.orange)
                .accessibilityHidden(true)
        }
        .padding()
    }

    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView()
                .controlSize(.small)
            Text(
                String(
                    localized: "cloudStorageConflictLoadingVersions",
                    defaultValue: "Loading local and cloud versions…"
                )
            )
            .font(.callout)
            .foregroundStyle(.secondary)
        }
    }

    private func errorView(_ error: Error) -> some View {
        VStack(spacing: 14) {
            Image(systemSymbol: .exclamationmarkTriangle)
                .font(.largeTitle)
                .foregroundStyle(.orange)

            Text(
                String(
                    localized: "cloudStorageConflictLoadFailed",
                    defaultValue: "Unable to Load Versions"
                )
            )
            .font(.headline)

            Text(error.localizedDescription)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button {
                Task { await loadVersions() }
            } label: {
                Text(.localizable(.generalButtonRetry))
            }
            .modernButtonStyle(style: .glassProminent, shape: .modern)
        }
        .padding()
    }

    private func versionSelection(_ prepared: PreparedSnapshot) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(
                    String(
                        localized: "cloudStorageConflictResolutionMessage",
                        defaultValue: "This file was changed both on this device and in cloud storage. Select the version you want to keep."
                    )
                )
                .font(.callout)
                .foregroundStyle(.secondary)

                if isCompact {
                    VStack(spacing: 12) {
                        versionCard(
                            .local,
                            file: prepared.localFile,
                            modifiedAt: prepared.snapshot.localModifiedAt
                        )
                        versionCard(
                            .remote,
                            file: prepared.remoteFile,
                            modifiedAt: prepared.snapshot.remoteItem.modifiedAt
                        )
                    }
                } else {
                    HStack(alignment: .top, spacing: 12) {
                        versionCard(
                            .local,
                            file: prepared.localFile,
                            modifiedAt: prepared.snapshot.localModifiedAt
                        )
                        versionCard(
                            .remote,
                            file: prepared.remoteFile,
                            modifiedAt: prepared.snapshot.remoteItem.modifiedAt
                        )
                    }
                }

                if let selectedVersion {
                    Text(selectionConsequence(selectedVersion))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .transition(.opacity)
                }
            }
            .padding(.horizontal)
            .padding(.bottom)
        }
    }

    private func versionCard(
        _ version: CloudStorageConflictVersion,
        file: ExcalidrawFile,
        modifiedAt: Date?
    ) -> some View {
        let isSelected = selectedVersion == version

        return Button {
            withAnimation(.smooth(duration: 0.2)) {
                selectedVersion = version
            }
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                Color.secondary.opacity(0.06)
                    .overlay {
                        ExcalidrawFileCover(
                            excalidrawFile: file,
                            generationPriority: .userInitiated
                        )
                        .scaledToFit()
                    }
                    .aspectRatio(4.0 / 3.0, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 6))

                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(versionTitle(version))
                            .font(.headline)

                        if let modifiedAt {
                            Text(modifiedAt.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer(minLength: 0)

                    Image(systemSymbol: isSelected ? .checkmarkCircleFill : .circle)
                        .font(.title2)
                        .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                }
            }
            .padding(10)
            .contentShape(Rectangle())
            .background {
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(
                        isSelected ? Color.accentColor : Color.secondary.opacity(0.18),
                        lineWidth: isSelected ? 2 : 1
                    )
            }
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
    }

    private var actions: some View {
        HStack(spacing: 10) {
            Spacer(minLength: 0)

            Button {
                cancelResolution()
            } label: {
                Text(.localizable(.generalButtonCancel))
            }
            .modernButtonStyle(style: .glass, shape: .modern)
            .keyboardShortcut(.cancelAction)

            Button {
                Task { await resolveSelectedVersion() }
            } label: {
                if isResolving {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Text(
                        String(
                            localized: "cloudStorageConflictUseSelectedVersion",
                            defaultValue: "Use Selected Version"
                        )
                    )
                }
            }
            .modernButtonStyle(style: .glassProminent, shape: .modern)
            .disabled(selectedVersion == nil || isResolving)
        }
        .padding()
    }

    private func loadVersions() async {
        isLoading = true
        loadingError = nil
        selectedVersion = nil

        do {
            let snapshot = try await documentStore.conflictSnapshot(for: reference)
            let previewGenerationID = UUID().uuidString
            let localFile = try ExcalidrawFile(
                data: snapshot.localData,
                id: "\(reference.id):conflict:\(previewGenerationID):local"
            )
            let remoteFile = try ExcalidrawFile(
                data: snapshot.remoteData,
                id: "\(reference.id):conflict:\(previewGenerationID):remote"
            )
            preparedSnapshot = PreparedSnapshot(
                snapshot: snapshot,
                localFile: localFile,
                remoteFile: remoteFile
            )
        } catch {
            loadingError = error
            preparedSnapshot = nil
        }
        isLoading = false
    }

    private func resolveSelectedVersion() async {
        guard let selectedVersion, let preparedSnapshot else { return }
        isResolving = true
        defer { isResolving = false }

        do {
            try await documentStore.resolveConflict(
                preparedSnapshot.snapshot,
                keeping: selectedVersion
            )
            dismiss()
        } catch {
            alertToast(error)
            if error as? CloudStorageError == .conflict {
                await loadVersions()
            }
        }
    }

    private func cancelResolution() {
        onCancel?()
        dismiss()
    }

    private func versionTitle(_ version: CloudStorageConflictVersion) -> String {
        switch version {
            case .local:
                String(
                    localized: "cloudStorageConflictLocalVersion",
                    defaultValue: "This Device"
                )
            case .remote:
                String(
                    localized: "cloudStorageConflictRemoteVersion",
                    defaultValue: "Cloud Version"
                )
        }
    }

    private func selectionConsequence(
        _ version: CloudStorageConflictVersion
    ) -> String {
        switch version {
            case .local:
                String(
                    localized: "cloudStorageConflictKeepLocalMessage",
                    defaultValue: "The version on this device will replace the cloud version."
                )
            case .remote:
                String(
                    localized: "cloudStorageConflictKeepRemoteMessage",
                    defaultValue: "The cloud version will replace the unsynced version on this device."
                )
        }
    }
}
