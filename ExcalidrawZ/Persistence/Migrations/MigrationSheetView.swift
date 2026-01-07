//
//  MigrationSheetView.swift
//  ExcalidrawZ
//
//  Created by Chocoford on 11/22/25.
//

import SwiftUI
import ChocofordUI
import SFSafeSymbols

struct MigrationProgressSheet: View {
    @Environment(\.containerHorizontalSizeClass) private var containerHorizontalSizeClass
    @Environment(\.dismiss) private var dismiss
    @Environment(\.alertToast) private var alertToast
    
    @ObservedObject var migrationState: MigrationState
    
    var migrationManager = MigrationManager.shared
    var isDev: Bool
    
    init(migrationState: MigrationState, isDev: Bool) {
        self.migrationState = migrationState
        self.isDev = isDev
        self._didArchiveFiles = State(initialValue: isDev)
    }
    
    @State private var isArchiving = false
    @State private var showArchiveExporter = false
    @State private var didArchiveFiles: Bool
    @State private var archiveFailedFiles: [FailedFileInfo] = []
    @State private var showFailedFilesAlert = false
    
    
    private var hasPendingMigrations: Bool {
        migrationState.migrations.contains { item in
            if case .pending = item.status {
                return true
            }
            return false
        }
    }
    
    private var hasCompletedWithErrors: Bool {
        migrationState.migrations.contains { item in
            if case .completedWithErrors = item.status {
                return true
            }
            return false
        }
    }
    
    private var sheetPadding: CGFloat {
        26
    }
    
    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 20) {
                // Fixed Title
                Text(titleText)
                    .font(.title)
                    .fontWeight(.semibold)
                    .padding(.top, 20)
                
                // Fixed Subtitle
                Text(subtitleText)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, containerHorizontalSizeClass != .compact ? 40 : 0)
            }
            .padding(.horizontal, sheetPadding)
            // Migration items list
            ScrollView {
                VStack(spacing: 12) {
                    ForEach(migrationState.migrations) { item in
                        MigrationItemRow(item: item)
                    }
                }
                .padding(.vertical, 20)
                .padding(.horizontal, sheetPadding)
            }
            
            VStack(spacing: 4) {
                // iCloud Sync Hint - shown during waitingForSync and idle phases
                if (migrationState.phase == .waitingForSync || migrationState.phase == .idle) {
                    VStack(spacing: 8) {
                        HStack(spacing: 8) {
                            Image(systemSymbol: .infoCircle)
                            Text(
                                localizable: migrationState.phase == .waitingForSync
                                ? .migrationICloudSyncHintWaitingForSyncTitle
                                : .migrationICloudSyncHintIdleTitle
                            )
                            .font(.headline)
                        }
                        Text(localizable: .migrationICloudSyncHintMessage)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity)
                    .background {
                        RoundedRectangle(cornerRadius: 16).fill(Color.accentColor.opacity(0.2))
                        RoundedRectangle(cornerRadius: 16).stroke(Color.accentColor)
                    }
                    .padding(.horizontal, sheetPadding)
                }
                
                // Bottom Buttons
                if (migrationState.phase == .idle || migrationState.phase == .waitingForSync) && hasPendingMigrations {
                    // Show Archive and Start buttons when migration is needed
                    ZStack {
                        if #available(macOS 13.0, *) {
                            let layout = if containerHorizontalSizeClass != .compact {
                                AnyLayout(HStackLayout(spacing: 12))
                            } else {
                                AnyLayout(VStackLayout(spacing: 12))
                            }
                            
                            layout {
                                actionsView()
                            }
                            .padding(.horizontal, sheetPadding)
                        } else {
                            HStack(spacing: 12) {
                                actionsView()
                            }
                            .padding(.horizontal, sheetPadding)
                        }
                    }
                    .disabled(migrationState.phase == .waitingForSync)
                } else if migrationState.phase == .completed && hasCompletedWithErrors {
                    // Show two buttons when migration completed with errors
                    if #available(macOS 13.0, *) {
                        let layout = if containerHorizontalSizeClass != .compact {
                            AnyLayout(HStackLayout(spacing: 12))
                        } else {
                            AnyLayout(VStackLayout(spacing: 12))
                        }
                        
                        layout {
                            errorActionsView()
                        }
                        .padding(.horizontal, sheetPadding)
                    } else {
                        HStack(spacing: 12) {
                            errorActionsView()
                        }
                        .padding(.horizontal, sheetPadding)
                    }
                } else {
                    // Single button for other states (except waitingForSync)
                    Button {
                        handleButtonTap()
                    } label: {
                        Text(buttonTitle)
                            .frame(maxWidth: .infinity)
                    }
                    .modernButtonStyle(style: .glassProminent, size: .large, shape: .capsule)
                    .disabled(!isButtonEnabled)
                    .padding(.horizontal, sheetPadding)
                }
            }
        }
        .padding(.vertical, sheetPadding)
        .overlay(alignment: .topTrailing) {
            if migrationState.phase == .waitingForSync {
                ZStack {
                    if #available(macOS 15.0, iOS 18.0, *) {
                        Image(systemSymbol: .arrowTrianglehead2ClockwiseRotate90)
                            .symbolEffect(.rotate, isActive: true)
                    } else {
                        Image(systemSymbol: .arrowTriangle2Circlepath)
                    }
                }
                .foregroundStyle(.secondary)
                .padding(20)
            }
        }
#if os(macOS)
        .frame(width: 500, height: 500)
#endif
        .interactiveDismissDisabled(!canDismiss)
        .archiveFilesExporter(
            isPresented: $showArchiveExporter,
            context: PersistenceController.shared.container.viewContext
        ) { result in
            handleArchiveResult(result)
        } onCancellation: {
            isArchiving = false
        }
        .overlay(alignment: .top) {
            if showFailedFilesAlert && !archiveFailedFiles.isEmpty {
                failedFilesAlertView
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
    }
    
    /// Alert view for failed files (toast-like overlay)
    @ViewBuilder
    private var failedFilesAlertView: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack(spacing: 8) {
                Image(systemSymbol: .exclamationmarkTriangle)
                    .foregroundStyle(.orange)
                Text(localizable: .migrationArchiveFailedItemsTitle(archiveFailedFiles.count))
                    .font(.headline)
                    .foregroundStyle(.primary)
                Spacer()
                Button {
                    withAnimation {
                        showFailedFilesAlert = false
                    }
                } label: {
                    Image(systemSymbol: .xmark)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            
            // Failed files list (scrollable if many)
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(archiveFailedFiles.prefix(5)) { failedFile in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(failedFile.fileName)
                                .font(.body)
                                .fontWeight(.medium)
                            Text(failedFile.error)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                    
                    if archiveFailedFiles.count > 5 {
                        Text(localizable: .generalAndXXXMore(archiveFailedFiles.count - 5))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.top, 4)
                    }
                }
            }
            .frame(maxHeight: 200)
        }
        .padding(16)
        .background {
            RoundedRectangle(cornerRadius: 16)
                .fill(.regularMaterial)
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.orange, lineWidth: 2)
        }
        .shadow(color: .black.opacity(0.2), radius: 10, x: 0, y: 5)
        .padding(.horizontal, sheetPadding)
        .padding(.top, sheetPadding)
        .onAppear {
            // Auto-dismiss after 10 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 10) {
                withAnimation {
                    showFailedFilesAlert = false
                }
            }
        }
    }
    
    @MainActor @ViewBuilder
    private func actionsView() -> some View {
        Button {
            isArchiving = true
            Task {
                await archiveFiles()
            }
        } label: {
            if isArchiving {
                HStack {
                    ProgressView()
                        .controlSize(.small)
                    Text(localizable: .migrationArchivingTitle)
                }
                .frame(maxWidth: .infinity)
            } else {
                Text(localizable: .migrationTooltipArchiveFirst)
                    .frame(maxWidth: .infinity)
            }
        }
        .modernButtonStyle(style: .glass, size: .large, shape: .capsule)
        .disabled(isArchiving)
        
        var isMigrating: Bool {
            if case .migrating = migrationState.phase { true } else { false }
        }
        
        Button {
            if !didArchiveFiles {
                return
            }
            Task {
                await runMigrations()
            }
        } label: {
            Text(localizable: .migrationButtonStartMigration)
                .frame(maxWidth: .infinity)
                .opacity(isMigrating ? 0 : 1)
                .overlay {
                    if isMigrating {
                        ProgressView().controlSize(.small)
                    }
                }
        }
        .if(!didArchiveFiles) {
            $0
                .opacity(0.5)
                .popoverHelp(.localizable(.migrationDownloadTooltip))
        }
        .modernButtonStyle(style: .glassProminent, size: .large, shape: .capsule)
        .disabled(isArchiving)
    }
    
    @MainActor @ViewBuilder
    private func errorActionsView() -> some View {
        var isMigrating: Bool {
            if case .migrating = migrationState.phase { true } else { false }
        }
        
        // Left button: Skip and continue with auto-resolve
        Button {
            Task {
                await runMigrations(autoResolveErrors: true)
            }
        } label: {
            Text(localizable: .migrationButtonSkipAndContinue)
                .frame(maxWidth: .infinity)
                .opacity(isMigrating ? 0 : 1)
                .overlay {
                    if isMigrating {
                        ProgressView().controlSize(.small)
                    }
                }
        }
        .modernButtonStyle(style: .glass, size: .large, shape: .capsule)
        .disabled(isMigrating)
        
        // Right button: Retry (recommended)
        Button {
            Task {
                await runMigrations(autoResolveErrors: false)
            }
        } label: {
            Text(localizable: .generalButtonRetry)
                .frame(maxWidth: .infinity)
                .opacity(isMigrating ? 0 : 1)
                .overlay {
                    if isMigrating {
                        ProgressView().controlSize(.small)
                    }
                }
        }
        .modernButtonStyle(style: .glassProminent, size: .large, shape: .capsule)
        .disabled(isMigrating)
    }
    
    private func isCurrentlyMigrating(_ item: MigrationItem) -> Bool {
        if case .migrating = item.status {
            return true
        }
        return false
    }
    
    private var titleText: String {
        switch migrationState.phase {
            case .idle:
                return hasPendingMigrations
                ? String(localizable: .migrationPhaseIdleWithPendingTitle)
                : String(localizable: .migrationPhaseIdleWithoutPendingTitle)
            case .waitingForSync:
                return String(localizable: .migrationPhaseWaitingForSyncTitle)
            case .checking:
                return String(localizable: .migrationPhaseCheckingTitle)
            case .migrating, .progress:
                return String(localizable: .migrationPhaseInProgressTitle)
            case .completed:
                return String(localizable: .migrationPhaseCompletedTitle)
            case .error:
                return String(localizable: .migrationPhaseErrorTitle)
            case .closed:
                return String(localizable: .migrationPhaseClosedTitle)
        }
    }
    
    private var subtitleText: String {
        switch migrationState.phase {
            case .idle:
                return hasPendingMigrations
                ? String(localizable: .migrationPhaseidleWithPendingSubtitle)
                : String(localizable: .migrationPhaseIdleWithoutPendingSubtitle)
            case .waitingForSync:
                return String(localizable: .migrationPhaseWaitingForSyncSubtitle)
            case .checking:
                return String(localizable: .migrationPhaseCheckingSubtitle)
            case .migrating, .progress:
                return String(localizable: .migrationPhaseInProgressSubtitle)
            case .completed:
                return String(localizable: .migrationPhaseCompletedSubtitle)
            case .error:
                return String(localizable: .migrationPhaseErrorSubtitle)
            case .closed:
                return String(localizable: .migrationPhaseClosedSubtitle)
        }
    }
    
    private func handleButtonTap() {
        switch migrationState.phase {
            case .idle:
                dismiss()
            case .completed:
                dismiss()
            case .error:
                Task {
                    await runMigrations()
                }
            default:
                break
        }
    }
    
    private var buttonTitle: String {
        switch migrationState.phase {
            case .idle:
                return String(localizable: .generalButtonClose)
            case .waitingForSync:
                return String(localizable: .migrationPhaseWaitingForSyncButtonTitle)
            case .checking, .migrating, .progress:
                return String(localizable: .migrationPhaseMigratingButtonTitle)
            case .completed:
                return String(localizable: .generalButtonDone)
            case .error:
                return String(localizable: .generalButtonRetry)
            case .closed:
                return String(localizable: .generalButtonDone)
        }
    }
    
    private var isButtonEnabled: Bool {
        switch migrationState.phase {
            case .idle, .completed, .error:
                return true
            default:
                return false
        }
    }
    
    private var canDismiss: Bool {
        switch migrationState.phase {
            case .completed:
                return true
            case .idle:
                return !hasPendingMigrations || isDev
            case .waitingForSync:
                return false // Cannot dismiss while waiting for CloudKit sync
            default:
                return false
        }
    }
    
    private func runMigrations(autoResolveErrors: Bool = false) async {
        do {
            try await migrationManager.runPendingMigrations(state: migrationState, autoResolveErrors: autoResolveErrors)
        } catch {
            alertToast(error)
        }
    }
    
    private func archiveFiles() async {
        // Trigger the file exporter
        await MainActor.run {
            showArchiveExporter = true
        }
    }
    
    private func handleArchiveResult(_ result: Result<ArchiveResult, Error>) {
        isArchiving = false
        
        switch result {
            case .success(let archiveResult):
                didArchiveFiles = true
                
                // Store failed files if any
                archiveFailedFiles = archiveResult.failedFiles
                
                if archiveResult.failedFiles.isEmpty {
                    // All files archived successfully
                    alertToast(
                        .init(
                            displayMode: .hud,
                            type: .complete(.green),
                            title: String(localizable: .migrationAlertToastArchiveSucessTitle(archiveResult.url.lastPathComponent))
                        )
                    )
                } else {
                    // Show failed files alert after a delay
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        showFailedFilesAlert = true
                    }
                }
                
            case .failure(let error):
                // User cancelled or error occurred
                if (error as NSError).code != NSUserCancelledError {
                    alertToast(error)
                }
        }
    }
}

struct MigrationItemRow: View {
    let item: MigrationItem
    
    @State private var isExpanded: Bool = false
    
    @State private var isHovered = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                // Status Icon
                statusIcon
                
                // Migration Name
                Text(item.name)
                    .font(.headline)
                
                Spacer()
                
                Image(systemSymbol: .chevronRight)
                    .rotationEffect(isExpanded ? .degrees(90) : .zero)
            }
            
            // Expanded Progress View
            if isExpanded {
                VStack(alignment: .leading, spacing: 10) {
                    Text(item.description)
                    
                    if case .migrating(let progress, let description) = item.status {
                        VStack(alignment: .leading, spacing: 4) {
                            ProgressView(value: progress)
                                .progressViewStyle(.linear)
                            
                            Text(description)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } else if case .completedWithErrors(let failedItems) = item.status {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(localizable: .migrationItemFailedItemsTitle(failedItems.count))
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundStyle(.orange)
                            VStack(alignment: .leading, spacing: 4) {
                                ForEach(failedItems) { failedItem in
                                    HStack {
                                        Text(failedItem.name)
                                            .font(.caption)
                                            .foregroundStyle(.orange)
                                        Spacer()
                                        Text(failedItem.error)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    } else if case .failed(let error, let progress) = item.status {
                        VStack(alignment: .leading, spacing: 4) {
                            ProgressView(value: progress)
                                .progressViewStyle(.linear)
                                .foregroundStyle(.red)
                            
                            Text(error)
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                    }
                }
                .padding(.leading, 24)
            }
        }
        .padding()
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation {
                isExpanded.toggle()
            }
        }
        .onHover { isHovered in
            withAnimation {
                self.isHovered = isHovered
            }
        }
        .background {
            ZStack {
                RoundedRectangle(cornerRadius: 24)
                    .fill(backgroundStyle)
                RoundedRectangle(cornerRadius: 24)
                    .stroke(borderColor, lineWidth: 1)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .compositingGroup()
        .onChange(of: item.status) { newValue in
            withAnimation {
                if case .migrating = newValue {
                    isExpanded =  true
                } else if case .completedWithErrors = newValue {
                    isExpanded =  true
                } else if case .failed = newValue {
                    isExpanded =  true
                } else {
                    isExpanded =  false
                }
            }
        }
    }
    
    private var backgroundStyle: AnyShapeStyle {
        if case .completedWithErrors = item.status {
            return AnyShapeStyle(Color.yellow.opacity(0.1))
        }
        return AnyShapeStyle(Material.ultraThickMaterial)
    }
    
    private var borderColor: Color {
        if case .completedWithErrors = item.status {
            return Color.yellow
        }
        return .secondary.opacity(0.5)
    }
    
    @ViewBuilder
    private var statusIcon: some View {
        switch item.status {
            case .pending:
                Image(systemSymbol: .circle)
                    .foregroundStyle(.secondary)
            case .checking:
                ProgressView()
                    .controlSize(.small)
            case .skipped, .completed:
                Image(systemSymbol: .checkmarkCircle)
                    .foregroundStyle(.green)
            case .completedWithErrors:
                Image(systemSymbol: .exclamationmarkTriangleFill)
                    .foregroundStyle(.yellow)
            case .migrating:
                ProgressView()
                    .controlSize(.small)
            case .failed:
                Image(systemSymbol: .exclamationmarkCircleFill)
                    .foregroundStyle(.red)
        }
    }
}
