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
                            Text(migrationState.phase == .waitingForSync ? "Waiting for iCloud sync to complete..." : "Checking for iCloud updates...")
                                .font(.headline)
                        }
                        Text("If you've already migrated on another device, the app will continue automatically after sync.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.horizontal, sheetPadding)
                    .padding(.vertical, 12)
                    .background {
                        RoundedRectangle(cornerRadius: 16).fill(Color.accentColor.opacity(0.2))
                        RoundedRectangle(cornerRadius: 16).stroke(Color.accentColor)
                    }
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
        .frame(
            width: containerHorizontalSizeClass != .compact ? 500 : nil,
            height: containerHorizontalSizeClass != .compact ? 500 : nil
        )
        .interactiveDismissDisabled(!canDismiss)
        .archiveFilesExporter(
            isPresented: $showArchiveExporter,
            context: PersistenceController.shared.container.viewContext
        ) { result in
            handleArchiveResult(result)
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
                    Text("Archiving...")
                }
                .frame(maxWidth: .infinity)
            } else {
                Text("Archive Files First")
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
            Text("Start Migration")
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
                .popoverHelp("Please archive files first")
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
            Text("Skip and Continue")
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
            Text("Retry")
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
                return hasPendingMigrations ? "Migration Required" : "No Migration Needed"
            case .waitingForSync:
                return "Waiting for iCloud Sync..."
            case .checking:
                return "Checking for migrations..."
            case .migrating, .progress:
                return "Migrating your data"
            case .completed:
                return "Migration Completed"
            case .error:
                return "Migration Failed"
            case .closed:
                return "Migration Completed"
        }
    }

    private var subtitleText: String {
        switch migrationState.phase {
            case .idle:
                return hasPendingMigrations
                    ? "We need to update your data to work with the latest version. You can archive your files first for safety."
                    : "Your data is up to date."
            case .waitingForSync:
                return "Checking for updates from iCloud before proceeding..."
            case .checking:
                return "Checking if any migrations are needed..."
            case .migrating, .progress:
                return "Please wait while we update your data to work better with the latest version of the app"
            case .completed:
                return "Your data has been successfully updated."
            case .error:
                return "An error occurred during the migration process."
            case .closed:
                return "Your data has been successfully updated."
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
                return "Close"
            case .waitingForSync:
                return "Waiting for syncing..."
            case .checking, .migrating, .progress:
                return "Migrating..."
            case .completed:
                return "Done"
            case .error:
                return "Retry"
            case .closed:
                return "Done"
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

    private func handleArchiveResult(_ result: Result<URL, Error>) {
        isArchiving = false

        switch result {
        case .success(let url):
            didArchiveFiles = true
            alertToast(
                .init(displayMode: .hud, type: .complete(.green), title: "Files archived successfully to \(url.lastPathComponent)")
            )

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
                            Text("Failed Items (\(failedItems.count)):")
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
