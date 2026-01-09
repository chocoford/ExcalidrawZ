//
//  StartupSyncModifier.swift
//  ExcalidrawZ
//
//  Created by Claude on 2025/12/30.
//

import SwiftUI
import Logging

/// View modifier that enables FileStorage sync after migration completes
/// Listens for migration phase to become .closed, then:
/// 1. Calls FileStorageManager.enableSync() to initialize SyncCoordinator
/// 2. Calls FileStorageManager.performStartupSync() to perform DiffScan
struct StartupSyncModifier: ViewModifier {
    private let logger = Logger(label: "StartupSyncModifier")

    @EnvironmentObject private var migrationState: MigrationState
    @State private var hasEnabledSync = false

    func body(content: Content) -> some View {
        content
            .onChange(of: migrationState.phase) { newPhase in
                if newPhase == .closed && !hasEnabledSync {
                    logger.info("Migration phase → .closed, triggering sync enable")
                    hasEnabledSync = true
                    Task {
                        await enableSyncAndPerformStartupSync()
                    }
                }
            }
    }

    private func enableSyncAndPerformStartupSync() async {
        // Step 1: Enable sync (initializes SyncCoordinator)
        logger.info("Enabling FileStorage sync...")
        await FileStorageManager.shared.enableSync()

        // Step 2: Perform startup sync (DiffScan)
        logger.info("Starting DiffScan...")
        do {
            try await FileStorageManager.shared.performStartupSync()
            logger.info("Startup sync completed")
        } catch {
            logger.error("Startup sync failed: \(error.localizedDescription)")
        }
    }
}

extension View {
    /// Apply StartupSyncModifier to enable file sync after migration
    func startupSync() -> some View {
        modifier(StartupSyncModifier())
    }
}
