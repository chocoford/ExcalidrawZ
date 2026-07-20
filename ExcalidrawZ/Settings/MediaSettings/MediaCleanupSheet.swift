//
//  MediaCleanupSheet.swift
//  ExcalidrawZ
//
//  Created by Codex on 2026/07/20.
//

import ChocofordUI
import CoreData
import SFSafeSymbols
import SwiftUI

struct MediaCleanupSheet: View {
    private enum SidebarSelection: Hashable {
        case orphaned
        case historyOnly(NSManagedObjectID)
        case trashedFile(URL)
        case unverified
    }

    @Environment(\.alertToast) private var alertToast
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var viewContext

    @State private var analysis: MediaCleanupAnalysis?
    @State private var sidebarSelection: SidebarSelection?
    @State private var selectedMediaIDs: Set<NSManagedObjectID> = []
    @State private var selectedTrashedFileIDs: Set<URL> = []
    @State private var isLoading = true
    @State private var isCleaning = false
    @State private var errorMessage: String?
    @State private var isDeleteConfirmationPresented = false
    @State private var lockedFileAccessRequest: LockedFileAccessRequest?
    @State private var shouldScanAfterUnlockSheetDismisses = false

    var body: some View {
        NavigationSplitView {
            sidebarColumn
                .navigationTitle(.localizable(.settingsMediaCleanupTitle))
        } detail: {
            detail
        }
        .navigationSplitViewStyle(.balanced)
        .overlay(alignment: .topTrailing) {
            sheetControls
                .padding(12)
        }
#if os(macOS)
        .frame(minWidth: 760, idealWidth: 900, minHeight: 520, idealHeight: 640)
#endif
        .task {
            await scan()
        }
        .sheet(
            item: $lockedFileAccessRequest,
            onDismiss: {
                guard shouldScanAfterUnlockSheetDismisses else { return }
                shouldScanAfterUnlockSheetDismisses = false
                Task {
                    await scan(allowUnlockPrompt: false)
                }
            }
        ) { request in
            LockedFileAccessSheet(
                request: request,
                automaticallyRequestsSystemAuthentication: true
            )
        }
        .alert(
            String(localizable: .settingsMediaCleanupDeleteConfirmationTitle),
            isPresented: $isDeleteConfirmationPresented
        ) {
            Button(.localizable(.generalButtonCancel), role: .cancel) {}
            Button(.localizable(.sidebarFileRowDeletePermanentlyAlertButtonConfirm), role: .destructive) {
                Task {
                    await cleanSelectedCandidates()
                }
            }
        } message: {
            Text(deleteConfirmationMessage)
        }
        .interactiveDismissDisabled(isCleaning)
    }

    private var sheetControls: some View {
        HStack(spacing: 8) {
            Button(role: .destructive) {
                requestCleanup()
            } label: {
                if isCleaning {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Text(localizable: .generalButtonDelete)
                }
            }
            .modernButtonStyle(style: .glassProminent, size: .regular, shape: .capsule)
            .disabled((selectedCandidates.isEmpty && selectedTrashedFiles.isEmpty) || isCleaning)

            Button {
                dismiss()
            } label: {
                Image(systemSymbol: .xmark)
            }
            .modernButtonStyle(style: .glass, size: .regular, shape: .circle)
            .disabled(isCleaning)
            .accessibilityLabel(Text(localizable: .generalButtonClose))
        }
    }

    @ViewBuilder
    private var sidebarColumn: some View {
#if os(macOS)
        if #available(macOS 14.0, *) {
            sidebar
                .toolbar(removing: .sidebarToggle)
        } else {
            sidebar
        }
#else
        sidebar
#endif
    }

    @ViewBuilder
    private var sidebar: some View {
        if isLoading {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let analysis, !analysis.isEmpty {
            List(selection: $sidebarSelection) {
                orphanedSidebarRow(analysis.orphaned)
                    .tag(SidebarSelection.orphaned)

                if !analysis.historyOnly.isEmpty {
                    Section {
                        ForEach(analysis.historyOnly) { candidate in
                            historyOnlySidebarRow(candidate)
                                .tag(SidebarSelection.historyOnly(candidate.id))
                        }
                    } header: {
                        Text(localizable: .settingsMediaCleanupHistoryOnlyTitle)
                    }
                }

                if !analysis.trashedFiles.isEmpty {
                    Section {
                        ForEach(analysis.trashedFiles) { candidate in
                            trashedFileSidebarRow(candidate)
                                .tag(SidebarSelection.trashedFile(candidate.id))
                        }
                    } header: {
                        Text(localizable: .settingsMediaCleanupTrashedFilesTitle)
                    }
                }

                if !analysis.unverified.isEmpty {
                    Section {
                        unverifiedSidebarRow(analysis.unverified)
                            .tag(SidebarSelection.unverified)
                    }
                }
            }
            .listStyle(.sidebar)
        } else {
            Color.clear
        }
    }

    private func orphanedSidebarRow(_ candidates: [MediaCleanupCandidate]) -> some View {
        HStack(spacing: 10) {
            selectionButton(
                symbol: orphanedSelectionSymbol(candidates),
                isSelected: candidates.contains { selectedMediaIDs.contains($0.id) },
                isDisabled: candidates.isEmpty
            ) {
                toggleOrphanedSelection(candidates)
            }

            Image(systemSymbol: .photoStack)
                .foregroundStyle(.secondary)

            Text(localizable: .settingsMediaCleanupOrphanedTitle)
                .lineLimit(1)

            Spacer(minLength: 4)

            Text(candidates.count.formatted())
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
    }

    private func historyOnlySidebarRow(_ candidate: MediaCleanupCandidate) -> some View {
        HStack(spacing: 10) {
            selectionButton(
                symbol: selectedMediaIDs.contains(candidate.id) ? .checkmarkCircleFill : .circle,
                isSelected: selectedMediaIDs.contains(candidate.id)
            ) {
                toggleSelection(for: candidate.id)
            }

            if let item = mediaItem(for: candidate.id) {
                MediaItemGridCell(item: item, isSelected: false)
                    .frame(width: 38, height: 38)
                    .fixedSize()
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(candidate.sourceName)
                    .lineLimit(1)

                Label(
                    candidate.checkpointObjectIDs.count.formatted(),
                    systemSymbol: .clockArrowCirclepath
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .contentShape(Rectangle())
    }

    private func unverifiedSidebarRow(_ candidates: [MediaCleanupCandidate]) -> some View {
        HStack(spacing: 10) {
            Image(systemSymbol: .exclamationmarkTriangle)
                .foregroundStyle(.orange)

            Text(localizable: .settingsMediaCleanupUnverifiedTitle)
                .lineLimit(1)

            Spacer(minLength: 4)

            Text(candidates.count.formatted())
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
    }

    private func trashedFileSidebarRow(_ candidate: MediaCleanupTrashedFileCandidate) -> some View {
        HStack(spacing: 10) {
            selectionButton(
                symbol: selectedTrashedFileIDs.contains(candidate.id) ? .checkmarkCircleFill : .circle,
                isSelected: selectedTrashedFileIDs.contains(candidate.id)
            ) {
                toggleTrashedFileSelection(candidate.id)
            }

            Image(systemSymbol: .trash)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 2) {
                Text(candidate.name)
                    .lineLimit(1)
                Text(localizable: .settingsMediaCleanupMediaCount(candidate.mediaObjectIDs.count))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .contentShape(Rectangle())
    }

    private func selectionButton(
        symbol: SFSymbol,
        isSelected: Bool,
        isDisabled: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemSymbol: symbol)
                .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
        }
        .buttonStyle(.borderless)
        .disabled(isDisabled)
    }

    @ViewBuilder
    private var detail: some View {
        if isLoading {
            loadingDetail
        } else if let errorMessage {
            errorDetail(errorMessage)
        } else if let analysis, analysis.isEmpty {
            emptyDetail(analysis)
        } else if let analysis {
            switch sidebarSelection {
                case .orphaned:
                    orphanedDetail(analysis.orphaned, skippedCount: analysis.skippedCount)
                case .historyOnly(let mediaObjectID):
                    if let candidate = analysis.historyOnly.first(where: { $0.id == mediaObjectID }) {
                        historyOnlyDetail(candidate)
                    } else {
                        selectionPlaceholder
                    }
                case .trashedFile(let objectURI):
                    if let candidate = analysis.trashedFiles.first(where: { $0.id == objectURI }) {
                        trashedFileDetail(candidate)
                    } else {
                        selectionPlaceholder
                    }
                case .unverified:
                    unverifiedDetail(analysis.unverified)
                case nil:
                    selectionPlaceholder
            }
        }
    }

    private var loadingDetail: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text(localizable: .settingsMediaCleanupScanning)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorDetail(_ message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemSymbol: .exclamationmarkTriangle)
                .font(.title)
                .foregroundStyle(.secondary)
            Text(message)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button(.localizable(.generalButtonRetry)) {
                Task {
                    await scan()
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private func emptyDetail(_ analysis: MediaCleanupAnalysis) -> some View {
        VStack(spacing: 12) {
            Image(systemSymbol: .checkmarkCircle)
                .font(.system(size: 36))
                .foregroundStyle(.green)
            Text(localizable: .settingsMediaCleanupNothingToClean)
                .font(.headline)
            skippedItemsMessage(analysis.skippedCount)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private var selectionPlaceholder: some View {
        VStack(spacing: 10) {
            Image(systemSymbol: .photoStack)
                .font(.system(size: 36))
                .foregroundStyle(.secondary)
            Text(localizable: .settingsMediaCleanupTitle)
                .font(.headline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func orphanedDetail(
        _ candidates: [MediaCleanupCandidate],
        skippedCount: Int
    ) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(localizable: .settingsMediaCleanupOrphanedTitle)
                        .font(.title2.weight(.semibold))
                    Text(localizable: .settingsMediaCleanupOrphanedDescription)
                        .foregroundStyle(.secondary)
                    skippedItemsMessage(skippedCount)
                }

                if candidates.isEmpty {
                    Text(localizable: .settingsMediaCleanupNothingToClean)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 180)
                } else {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 120, maximum: 180), spacing: 8)],
                        spacing: 8
                    ) {
                        ForEach(candidates) { candidate in
                            candidateGridCell(candidate)
                        }
                    }
                }
            }
            .padding(20)
        }
        .navigationTitle(.localizable(.settingsMediaCleanupOrphanedTitle))
    }

    private func historyOnlyDetail(_ candidate: MediaCleanupCandidate) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if let item = mediaItem(for: candidate.id) {
                    MediaItemGridCell(
                        item: item,
                        isSelected: selectedMediaIDs.contains(candidate.id)
                    )
                    .frame(maxWidth: 360)
                    .onTapGesture {
                        toggleSelection(for: candidate.id)
                    }
                    .frame(maxWidth: .infinity)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(localizable: .settingsMediaCleanupHistoryOnlyTitle)
                        .font(.title2.weight(.semibold))
                    Text(localizable: .settingsMediaCleanupHistoryOnlyDescription)
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text(localizable: .checkpoints)
                        .font(.headline)

                    ForEach(checkpoints(for: candidate), id: \.objectID) { checkpoint in
                        FileCheckpointRowView(
                            checkpoint: checkpoint,
                            presentsDetail: false
                        )
                    }
                }
            }
            .padding(20)
        }
        .navigationTitle(candidate.sourceName)
    }

    private func unverifiedDetail(_ candidates: [MediaCleanupCandidate]) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(localizable: .settingsMediaCleanupUnverifiedTitle)
                        .font(.title2.weight(.semibold))
                    Text(localizable: .settingsMediaCleanupUnverifiedDescription)
                        .foregroundStyle(.secondary)
                }

                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 120, maximum: 180), spacing: 8)],
                    spacing: 8
                ) {
                    ForEach(candidates) { candidate in
                        if let item = mediaItem(for: candidate.id) {
                            MediaItemGridCell(item: item, isSelected: false)
                                .accessibilityLabel(candidate.sourceName)
                        }
                    }
                }
            }
            .padding(20)
        }
        .navigationTitle(.localizable(.settingsMediaCleanupUnverifiedTitle))
    }

    private func trashedFileDetail(_ candidate: MediaCleanupTrashedFileCandidate) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(candidate.name)
                        .font(.title2.weight(.semibold))
                    Text(localizable: .settingsMediaCleanupTrashedFilesDescription)
                        .foregroundStyle(.secondary)
                }

                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 120, maximum: 180), spacing: 8)],
                    spacing: 8
                ) {
                    ForEach(candidate.mediaObjectIDs, id: \.self) { objectID in
                        if let item = mediaItem(for: objectID) {
                            MediaItemGridCell(
                                item: item,
                                isSelected: selectedTrashedFileIDs.contains(candidate.id)
                            )
                            .contentShape(Rectangle())
                            .onTapGesture {
                                toggleTrashedFileSelection(candidate.id)
                            }
                        }
                    }
                }
            }
            .padding(20)
        }
        .navigationTitle(candidate.name)
    }

    private func candidateGridCell(_ candidate: MediaCleanupCandidate) -> some View {
        ZStack {
            if let item = mediaItem(for: candidate.id) {
                MediaItemGridCell(
                    item: item,
                    isSelected: selectedMediaIDs.contains(candidate.id)
                )
                .overlay(alignment: .topTrailing) {
                    Image(
                        systemSymbol: selectedMediaIDs.contains(candidate.id)
                            ? .checkmarkCircleFill
                            : .circle
                    )
                    .font(.title3)
                    .foregroundStyle(
                        selectedMediaIDs.contains(candidate.id)
                            ? Color.accentColor
                            : Color.secondary
                    )
                    .padding(6)
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    toggleSelection(for: candidate.id)
                }
                .accessibilityLabel(candidate.sourceName)
            }
        }
    }

    @ViewBuilder
    private func skippedItemsMessage(_ count: Int) -> some View {
        if count > 0 {
            Text(localizable: .settingsMediaCleanupSkippedCount(count))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var allCandidates: [MediaCleanupCandidate] {
        guard let analysis else { return [] }
        return analysis.orphaned + analysis.historyOnly
    }

    private var selectedCandidates: [MediaCleanupCandidate] {
        allCandidates.filter { selectedMediaIDs.contains($0.id) }
    }

    private var selectedHistoryOnlyCandidates: [MediaCleanupCandidate] {
        selectedCandidates.filter { $0.kind == .historyOnly }
    }

    private var selectedTrashedFiles: [MediaCleanupTrashedFileCandidate] {
        guard let analysis else { return [] }
        return analysis.trashedFiles.filter { selectedTrashedFileIDs.contains($0.id) }
    }

    private var affectedCheckpointCount: Int {
        Set(selectedHistoryOnlyCandidates.flatMap(\.checkpointObjectIDs)).count
    }

    private var deleteConfirmationMessage: String {
        if selectedTrashedFiles.isEmpty {
            return String(
                localizable: .settingsMediaCleanupHistoryConfirmationMessage(
                    selectedHistoryOnlyCandidates.count,
                    affectedCheckpointCount
                )
            )
        }
        if selectedHistoryOnlyCandidates.isEmpty {
            return String(
                localizable: .settingsMediaCleanupTrashedFilesConfirmationMessage(
                    selectedTrashedFiles.count
                )
            )
        }
        return String(localizable: .settingsMediaCleanupDeleteConfirmationMessage)
    }

    private func mediaItem(for objectID: NSManagedObjectID) -> MediaItem? {
        guard let object = try? viewContext.existingObject(with: objectID) else {
            return nil
        }
        return object as? MediaItem
    }

    private func checkpoints(for candidate: MediaCleanupCandidate) -> [FileCheckpoint] {
        candidate.checkpointObjectIDs
            .compactMap { objectID in
                try? viewContext.existingObject(with: objectID)
            }
            .compactMap { $0 as? FileCheckpoint }
            .sorted { ($0.updatedAt ?? .distantPast) > ($1.updatedAt ?? .distantPast) }
    }

    private func orphanedSelectionSymbol(_ candidates: [MediaCleanupCandidate]) -> SFSymbol {
        let selectedCount = candidates.filter { selectedMediaIDs.contains($0.id) }.count
        if selectedCount == 0 {
            return .circle
        }
        if selectedCount == candidates.count {
            return .checkmarkCircleFill
        }
        return .minusCircleFill
    }

    private func toggleOrphanedSelection(_ candidates: [MediaCleanupCandidate]) {
        let candidateIDs = Set(candidates.map(\.id))
        if candidateIDs.isSubset(of: selectedMediaIDs) {
            selectedMediaIDs.subtract(candidateIDs)
        } else {
            selectedMediaIDs.formUnion(candidateIDs)
        }
    }

    private func toggleSelection(for objectID: NSManagedObjectID) {
        if selectedMediaIDs.contains(objectID) {
            selectedMediaIDs.remove(objectID)
        } else {
            selectedMediaIDs.insert(objectID)
        }
    }

    private func toggleTrashedFileSelection(_ objectURI: URL) {
        if selectedTrashedFileIDs.contains(objectURI) {
            selectedTrashedFileIDs.remove(objectURI)
        } else {
            selectedTrashedFileIDs.insert(objectURI)
        }
    }

    private func requestCleanup() {
        if selectedHistoryOnlyCandidates.isEmpty, selectedTrashedFiles.isEmpty {
            Task {
                await cleanSelectedCandidates()
            }
        } else {
            isDeleteConfirmationPresented = true
        }
    }

    @MainActor
    private func scan(allowUnlockPrompt: Bool = true) async {
        isLoading = true
        errorMessage = nil
        selectedMediaIDs.removeAll()
        selectedTrashedFileIDs.removeAll()

        do {
            if allowUnlockPrompt,
               let lockedFile = try await PersistenceController.shared.fileRepository
                   .listLockedFiles(includeTrash: true)
                   .first(where: { $0.lockState == .locked }) {
                shouldScanAfterUnlockSheetDismisses = true
                lockedFileAccessRequest = LockedFileAccessRequest(
                    mode: .unlock,
                    fileObjectID: lockedFile.fileObjectID,
                    fileName: lockedFile.name,
                    fileID: lockedFile.id
                )
                return
            }

            let analysis = try await MediaCleanupCoordinator.shared.scan()
            self.analysis = analysis
            if !analysis.orphaned.isEmpty {
                sidebarSelection = .orphaned
            } else if let firstTrashedFile = analysis.trashedFiles.first {
                sidebarSelection = .trashedFile(firstTrashedFile.id)
            } else if let firstHistoryOnly = analysis.historyOnly.first {
                sidebarSelection = .historyOnly(firstHistoryOnly.id)
            } else if !analysis.unverified.isEmpty {
                sidebarSelection = .unverified
            } else {
                sidebarSelection = nil
            }
        } catch {
            analysis = nil
            sidebarSelection = nil
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    @MainActor
    private func cleanSelectedCandidates() async {
        let candidates = selectedCandidates
        let trashedFiles = selectedTrashedFiles
        guard !candidates.isEmpty || !trashedFiles.isEmpty else { return }

        isCleaning = true
        defer { isCleaning = false }
        do {
            let result = try await MediaCleanupCoordinator.shared.clean(candidates)

            let fileObjectIDs = trashedFiles.compactMap { candidate in
                candidate.kind == .file ? candidate.objectID : nil
            }
            try await PersistenceController.shared.fileRepository.delete(
                fileObjectIDs: fileObjectIDs,
                forcePermanently: true
            )

            for candidate in trashedFiles where candidate.kind == .collaborationFile {
                try await PersistenceController.shared.collaborationFileRepository.delete(
                    collaborationFileObjectID: candidate.objectID
                )
            }

            // Repository deletion performs the same global-reference cleanup.
            // A final pass handles media shared between multiple selected files,
            // after every selected owner has been removed.
            _ = try await MediaCleanupCoordinator.shared.cleanOrphanedMedia(
                withObjectURIs: trashedFiles
                    .flatMap(\.mediaObjectIDs)
                    .map { $0.uriRepresentation() }
            )

            let successMessage: String
            if trashedFiles.isEmpty {
                successMessage = String(
                    localizable: .settingsMediaCleanupSuccessMessage(
                        result.deletedMediaCount,
                        result.deletedCheckpointCount
                    )
                )
            } else {
                successMessage = String(
                    localizable: .settingsMediaCleanupFilesDeletedMessage(trashedFiles.count)
                )
            }
            alertToast(
                .init(
                    displayMode: .hud,
                    type: .complete(.green),
                    title: String(localizable: .generalSuccess),
                    subTitle: successMessage
                )
            )
            await scan(allowUnlockPrompt: false)
        } catch {
            alertToast(error)
        }
    }
}
