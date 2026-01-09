//
//  ConflictResolutionSheetView.swift
//  ExcalidrawZ
//
//  Created by Chocoford on 12/25/25.
//

import SwiftUI
import Logging

import ChocofordUI

/// Sheet for resolving iCloud file conflicts
///
/// Displays all conflicting versions and allows user to choose which to keep.
struct ConflictResolutionSheetView: View {
    @Environment(\.containerHorizontalSizeClass) private var containerHorizontalSizeClass
    @Environment(\.dismiss) private var dismiss
    @Environment(\.alertToast) private var alertToast

    var fileURL: URL
    var onResolved: () -> Void
    var onCancelled: () -> Void

    var resolver: ICloudConflictResolver

    @State private var versions: [FileVersion] = []
    @State private var selectedVersion: FileVersion?
    @State private var isLoading = true
    @State private var isResolving = false
    @State private var error: Error?

    private let logger = Logger(label: "ConflictResolutionSheet")

    private var isCompact: Bool {
        containerHorizontalSizeClass == .compact
    }

    init(
        fileURL: URL,
        onResolved: @escaping () -> Void,
        onCancelled: @escaping () -> Void,
    ) {
        self.fileURL = fileURL
        self.onResolved = onResolved
        self.onCancelled = onCancelled
        self.resolver = ICloudConflictResolver(fileURL: fileURL)
    }

    var body: some View {
        navigationStack {
            VStack(spacing: 0) {
                header()

                // Version list
                if isLoading {
                    loadingView()
                } else if let error = error {
                    errorView(error: error)
                } else if versions.isEmpty {
                    emptyView()
                } else {
                    ScrollView {
                        VStack(spacing: 12) {
                            ForEach(versions) { version in
                                VersionRow(
                                    version: version,
                                    isSelected: selectedVersion?.id == version.id,
                                    onSelect: {
                                        selectedVersion = version
                                    }
                                )
                            }
                        }
                        .padding()
                    }
                }


#if os(macOS)
                // Action buttons
                HStack(spacing: 10) {
                    Spacer()
                    actions()
                }
                .padding()
#endif
            }
            .frame(width: isCompact ? nil : 600, height: isCompact ? nil : 500)
            .navigationTitle("Resolve Conflict")
#if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(.localizable(.generalButtonCancel)) {
                        onCancelled()
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .topBarTrailing) {
                    AsyncButton("Keep") {
                        try await resolveConflict()
                    }
                    .disabled(selectedVersion == nil || isResolving)
                }
            }
#endif
        }
        .task {
            loadVersions()
        }
    }
    
    @MainActor @ViewBuilder
    private func navigationStack<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        if #available(macOS 13.0, *) {
            NavigationStack {
                content()
            }
        } else {
            NavigationView {
                content()
            }
        }
    }

    @MainActor @ViewBuilder
    private func header() -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemSymbol: .exclamationmarkTriangleFill)
                    .foregroundStyle(.orange)
                
                Text(fileURL.lastPathComponent)

                Spacer()
            }
            .font(.headline)

            Text("Multiple versions of this file exist. Choose which version to keep:")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding()
    }
    
    @MainActor @ViewBuilder
    private func loadingView() -> some View {
        VStack(spacing: 0) {
            Spacer()
            ProgressView(.localizable(.generalLoading))
                .controlSize(.large)
            Spacer()
        }
    }
    
    @MainActor @ViewBuilder
    private func errorView(error: Error) -> some View {
        VStack(spacing: 0) {
            Spacer()
            VStack(spacing: 16) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.largeTitle)
                    .foregroundStyle(.red)

                Text("Failed to load versions")
                    .font(.headline)

                Text(error.localizedDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                Button("Try Again") {
                    loadVersions()
                }
                .modernButtonStyle(style: .glassProminent, shape: .modern)
            }
            .padding()
            Spacer()
        }
    }
    
    @MainActor @ViewBuilder
    private func emptyView() -> some View {
        VStack(spacing: 0) {
            Spacer()
            VStack(spacing: 16) {
                Image(systemName: "questionmark.circle")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
                
                Text("No conflicting versions found")
                    .font(.headline)
                
                Button("Close") {
                    dismiss()
                }
                .buttonStyle(.bordered)
            }
            .padding()
            Spacer()
        }
    }
    
    @MainActor @ViewBuilder
    private func actions() -> some View {
        Button(.localizable(.generalButtonCancel)) {
            onCancelled()
            dismiss()
        }
        .modernButtonStyle(style: .glass, shape: .modern)
        .keyboardShortcut(.cancelAction)

        AsyncButton("Keep Selected Version") {
            try await resolveConflict()
        }
        .modernButtonStyle(style: .glassProminent, shape: .modern)
        .disabled(selectedVersion == nil || isResolving)
    }
    
    // MARK: - Helper Methods

    private func loadVersions() {
        isLoading = true
        error = nil

        Task {
            do {
                let loadedVersions = try await resolver.getConflictVersions()

                await MainActor.run {
                    self.versions = loadedVersions
                    // Auto-select current version
                    self.selectedVersion = loadedVersions.first { $0.isCurrent }
                    self.isLoading = false
                }
            } catch {
                await MainActor.run {
                    self.error = error
                    self.isLoading = false
                }
                logger.error("Failed to load versions: \(error)")
            }
        }
    }

    private func resolveConflict() async throws {
        guard let selectedVersion = selectedVersion else { return }

        try await resolver.resolveConflict(keepingVersion: selectedVersion)
        
        await MainActor.run {
            isResolving = false
            onResolved()
            dismiss()
        }
        
        logger.info("Conflict resolved successfully")
    }
}

// MARK: - Version Row

private struct VersionRow: View {
    let version: FileVersion
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button {
            onSelect()
        } label: {
            HStack(spacing: 16) {
                // Selection indicator
                Image(systemSymbol: isSelected ? .checkmarkCircleFill : .circle)
                    .font(.title2)
                    .foregroundStyle(isSelected ? .blue : .secondary)

                VStack(alignment: .leading, spacing: 8) {
                    // Version name
                    HStack {
                        Text(version.displayName)
                            .font(.headline)

                        if version.isCurrent {
                            Text("(Current)")
                                .font(.caption)
                                .foregroundStyle(.blue)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.blue.opacity(0.1))
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                        }
                    }

                    // Metadata
                    HStack(spacing: 16) {
                        HStack(spacing: 4) {
                            Label {
                                Text(version.deviceName)
                            } icon: {
                                Image(systemSymbol: version.deviceName.contains("iPhone") ? .iphone : .desktopcomputer)
                            }
                        }
                        
                        HStack(spacing: 4) {
                            Label {
                                Text(formatDate(version.modificationDate))
                            } icon: {
                                Image(systemSymbol: .clock)
                            }
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Spacer()
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

// MARK: - Preview

#Preview {
    ConflictResolutionSheetView(
        fileURL: URL(fileURLWithPath: "/tmp/test.excalidraw"),
        onResolved: {},
        onCancelled: {}
    )
}
