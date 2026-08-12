//
//  CloudStorageFolderPicker.swift
//  ExcalidrawZ
//

import ChocofordUI
import SwiftUI

struct CloudStorageFolderPickerContext: Identifiable {
    let id = UUID()
    let providerID: CloudStorageProviderID
    let providerName: String
    let account: CloudStorageAccount
    let session: any CloudStorageSession
}

struct CloudStorageFolderPicker: View {
    @Environment(\.dismiss) private var dismiss

    let context: CloudStorageFolderPickerContext
    let onSelect: (CloudStorageItem) -> Void

    @StateObject private var model: CloudStorageFolderPickerModel
    @State private var hoveredFolderID: CloudStorageItemID?
    @State private var navigationDirection: NavigationDirection = .forward

    private enum NavigationDirection {
        case forward
        case backward
    }

    init(
        context: CloudStorageFolderPickerContext,
        onSelect: @escaping (CloudStorageItem) -> Void
    ) {
        self.context = context
        self.onSelect = onSelect
        self._model = StateObject(
            wrappedValue: CloudStorageFolderPickerModel(session: context.session)
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            if let errorMessage = model.errorMessage {
                errorBanner(errorMessage)
            }

            content
                .padding(16)
        }
        .task {
            await model.start()
        }
        .onDisappear {
            model.cancelPendingRequests()
        }
#if os(macOS)
        .frame(minWidth: 560, idealWidth: 680, minHeight: 480, idealHeight: 600)
#endif
    }

    private var header: some View {
        ZStack {
            VStack(spacing: 1) {
                Text(navigationTitle)
                    .font(.headline)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(context.account.displayName)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .padding(.horizontal, 116)
            .frame(maxWidth: .infinity)

            HStack(spacing: 8) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                }
                .modernButtonStyle(style: .glass, size: .large, shape: .circle)

                if model.path.count > 1 {
                    Button {
                        navigationDirection = .backward
                        Task { await model.goBack() }
                    } label: {
                        Image(systemName: "chevron.left")
                    }
                    .modernButtonStyle(style: .glass, size: .large, shape: .circle)
                    .disabled(model.isLoading)
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
                }

                Spacer(minLength: 80)

                Button("Choose") {
                    guard let folder = model.currentFolder else { return }
                    onSelect(folder)
                    dismiss()
                }
                .modernButtonStyle(style: .glassProminent, size: .large, shape: .modern)
                .disabled(model.currentFolder == nil || model.isLoading)
            }
            .padding(.horizontal, 12)
        }
        .frame(height: 68)
        .animation(.smooth(duration: 0.2), value: model.path.count > 1)
    }

    @ViewBuilder
    private var content: some View {
        if model.path.isEmpty {
            if model.isLoading || model.errorMessage == nil {
                initialLoadingState
            } else {
                initialErrorState
            }
        } else {
            ZStack {
                folderContent
                    .id(model.currentFolder?.id)
                    .transition(folderTransition)

                if model.isLoading {
                    ProgressView()
                        .controlSize(.small)
                }
            }
            .clipped()
        }
    }

    @ViewBuilder
    private var folderContent: some View {
        if model.folders.isEmpty,
           model.isLoading || model.errorMessage != nil {
            Color.clear
        } else if model.folders.isEmpty {
            emptyState
        } else {
            ScrollView {
                LazyVStack(spacing: 6) {
                    ForEach(model.folders) { folder in
                        folderRow(folder)
                    }
                }
            }
            .scrollIndicators(.automatic)
        }
    }

    private var initialLoadingState: some View {
        VStack(spacing: 10) {
            ProgressView()
                .controlSize(.small)
            Text("Loading Folders")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var initialErrorState: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(.secondary)
            Text("Unable to Load Folders")
                .font(.headline)
            Button("Try Again") {
                Task { await model.start() }
            }
            .modernButtonStyle(style: .glass, size: .regular, shape: .modern)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func folderRow(_ folder: CloudStorageItem) -> some View {
        HStack(spacing: 16) {
            Image(systemName: "folder.fill")
                .font(.system(size: 30, weight: .regular))
                .foregroundStyle(.blue)
                .frame(width: 42, height: 42)

            Text(folder.name)
                .font(.body)
                .foregroundStyle(.primary)
                .lineLimit(2)

            Spacer(minLength: 16)

            Image(systemName: "chevron.right")
                .font(.callout.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 64)
        .background {
            Capsule()
                .fill(folderRowBackground(for: folder))
        }
        .contentShape(Capsule())
        .onTapGesture {
            navigationDirection = .forward
            Task { await model.open(folder) }
        }
        .onHover { isHovered in
            hoveredFolderID = isHovered ? folder.id : nil
        }
        .allowsHitTesting(!model.isLoading)
        .animation(.easeOut(duration: 0.14), value: hoveredFolderID)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "folder")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(.secondary)
            Text("No Folders")
                .font(.headline)
            Text("Choose the current folder or go back.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.regularMaterial)
    }

    private var folderTransition: AnyTransition {
        switch navigationDirection {
            case .forward:
                return .asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal: .move(edge: .leading).combined(with: .opacity)
                )
            case .backward:
                return .asymmetric(
                    insertion: .move(edge: .leading).combined(with: .opacity),
                    removal: .move(edge: .trailing).combined(with: .opacity)
                )
        }
    }

    private func folderRowBackground(for folder: CloudStorageItem) -> Color {
        if hoveredFolderID == folder.id {
            return Color.secondary.opacity(0.12)
        }
        return .clear
    }

    private var navigationTitle: String {
        guard model.path.count > 1 else { return context.providerName }
        return model.currentFolder?.name ?? context.providerName
    }
}
