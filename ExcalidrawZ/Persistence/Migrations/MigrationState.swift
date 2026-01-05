//
//  MigrationState.swift
//  ExcalidrawZ
//
//  Created by Chocoford on 11/21/25.
//

import SwiftUI
import SwiftyAlert
import Combine
import CoreData
import Logging
import Network

enum MigrationPhase: Equatable {
    case idle
    case waitingForSync
    case checking
    case migrating(name: String)
    case progress(description: String, value: Double)
    case completed
    case error(String)

    case closed
    
    var isMigrating: Bool {
        switch self {
            case .migrating:
                true
            case .progress:
                true
            default:
                false
        }
    }
}

struct MigrationFailedItem: Identifiable, Equatable, Codable {
    let id: String
    let name: String
    let error: String
}

enum MigrationItemStatus: Equatable {
    case pending
    case checking
    case skipped
    case migrating(progress: Double, description: String)
    case completed
    case completedWithErrors([MigrationFailedItem])
    case failed(error: String, progress: Double)
}

struct MigrationItem: Identifiable, Equatable {
    let id: String
    let name: String
    var description: String
    var status: MigrationItemStatus
}

@MainActor
final class MigrationState: ObservableObject {

    @Published var phase: MigrationPhase = .idle
    @Published var isMigrationInProgress = false
    @Published var migrations: [MigrationItem] = []
    
    func initializeMigrations(_ migrationTypes: [any MigrationVersion.Type]) {
        migrations = migrationTypes.map { type in
            MigrationItem(
                id: type.name,
                name: type.name,
                description: type.description,
                status: .pending
            )
        }
    }

    func updateMigrationStatus(name: String, status: MigrationItemStatus) {
        if let index = migrations.firstIndex(where: { $0.name == name }) {
            migrations[index].status = status
        }
    }
    
    func getMigrationProgress(name: String) -> Double? {
        if let migration = migrations.first(where: { $0.name == name }) {
            if case .migrating(let progress, _) = migration.status {
                return progress
            }
        }
        return nil
    }
}

struct CoreDataMigrationModifier: ViewModifier {
    @AppStorage("DisableCloudSync") var isICloudDisabled: Bool = false

    @Environment(\.alertToast) private var alertToast

    @StateObject private var migrationState = MigrationState()
    @State private var showMigrationSheet = false
    @State private var continuousCloudKitMonitor: Task<Void, Never>?

    let migrationManager = MigrationManager.shared
    private let logger = Logger(label: "CoreDataMigrationModifier")

    #if DEBUG
    private let isDev = true
    #else
    private let isDev = false
    #endif

    private let syncTimeout: TimeInterval = 10 // 10 seconds timeout

    func body(content: Content) -> some View {
        content
            .environmentObject(migrationState)
            .sheet(isPresented: $showMigrationSheet) {
                migrationState.phase = .closed
                continuousCloudKitMonitor?.cancel()
            } content: {
                MigrationProgressSheet(
                    migrationState: migrationState,
                    isDev: isDev,
                )
                .swiftyAlert()
            }
            .onAppear {
                Task {
                    await startMigrationCheck()
                }
            }
    }

    private func startMigrationCheck() async {
        logger.info("Migration check started")

        // Step 1: Fast check if migration is needed (non-blocking)
        let needsMigration: Bool
        do {
            needsMigration = try await migrationManager.checkMigrationsNeeded(state: migrationState)
            logger.info("Migration needed: \(needsMigration)")
        } catch {
            logger.error("Migration check failed: \(error)")
            alertToast(error)
            migrationState.phase = .closed
            return
        }

        // Dev mode: always show sheet for testing
        // Production: only show if migration is actually needed
        if !isDev && !needsMigration {
            // No migration needed - fast path for users without pending migrations
            logger.info("No migration needed, phase → .closed")
            migrationState.phase = .closed
            return
        }
        
        showMigrationSheet = true

        // Step 2: Start CloudKit monitoring (initial sync + continuous monitoring)
        if !isICloudDisabled {
            logger.info("Phase → .waitingForSync")
            migrationState.phase = .waitingForSync
            startContinuousCloudKitMonitoring()
        } else {
            // No iCloud, go directly to idle
            logger.info("Phase → .idle (iCloud disabled)")
            migrationState.phase = .idle
        }
    }

    /// Check current network status
    /// - Returns: true if network is available, false otherwise
    private func checkNetworkStatus() async -> Bool {
        let networkMonitor = NWPathMonitor()
        let queue = DispatchQueue(label: "NetworkMonitor")
        networkMonitor.start(queue: queue)

        // Give monitor a moment to detect network status
        try? await Task.sleep(nanoseconds: UInt64(0.5 * 1e+9))

        let hasNetwork = networkMonitor.currentPath.status == .satisfied
        networkMonitor.cancel()

        return hasNetwork
    }

    /// Start CloudKit monitoring: handles initial sync wait + continuous monitoring
    /// This ensures we catch data synced from other devices that might need migration
    private func startContinuousCloudKitMonitoring() {
        logger.info("Starting CloudKit monitoring (initial sync + continuous)")

        continuousCloudKitMonitor = Task {
            // First, check network status
            let hasNetwork = await checkNetworkStatus()

            if !hasNetwork {
                logger.warning("⚠️ No network detected")
                await MainActor.run {
                    migrationState.phase = .error("No network connection detected. Migration will proceed with local data only.")
                }
                // Wait a bit to show the warning
                try? await Task.sleep(nanoseconds: UInt64(2 * 1e+9))
                await MainActor.run {
                    migrationState.phase = .idle
                }
                return
            }

            var debounceTask: Task<Void, Never>?
            let debounceInterval: TimeInterval = 5.0 // Wait 5s after last event
            var isFirstCheck = true // Track if this is the first recheck after initial sync

            // Set up CloudKit sync listener
            let listener = NotificationCenter.default.publisher(
                for: NSPersistentCloudKitContainer.eventChangedNotification
            ).sink { notification in
                guard let userInfo = notification.userInfo,
                      let event = userInfo["event"] as? NSPersistentCloudKitContainer.Event else {
                    return
                }

                // Only consider successful import events (data coming from iCloud)
                guard event.type == .import, event.succeeded else {
                    return
                }

                self.logger.debug("CloudKit import event received, will recheck migrations after debounce")

                // Cancel previous debounce task
                debounceTask?.cancel()

                // Start new debounce task
                debounceTask = Task {
                    try? await Task.sleep(nanoseconds: UInt64(1e+9 * debounceInterval))

                    guard !Task.isCancelled else { return }
                    guard !self.migrationState.phase.isMigrating else {
                        return
                    }

                    // Recheck if migration is needed
                    do {
                        let needsMigration = try await self.migrationManager.checkMigrationsNeeded(state: self.migrationState)
                        self.logger.info("Rechecked migrations after CloudKit sync: needsMigration = \(needsMigration)")

                        // If this is the first check after initial sync, move to idle
                        if isFirstCheck {
                            isFirstCheck = false
                            await MainActor.run {
                                self.migrationState.phase = .idle
                            }
                            self.logger.info("Initial sync completed, phase → .idle")
                        }

                        if needsMigration {
                            if case .error = self.migrationState.phase {
                                return
                            }
                            await MainActor.run {
                                showMigrationSheet = true
                                self.migrationState.phase = .idle
                            }
                        } else {
                            await MainActor.run {
                                self.migrationState.phase = .completed
                            }
                        }
                    } catch {
                        self.logger.error("Failed to recheck migrations: \(error.localizedDescription)")
                    }
                }
            }

            // Timeout for initial sync (10 seconds)
            Task {
                try? await Task.sleep(nanoseconds: UInt64(1e+9 * self.syncTimeout))
                if isFirstCheck {
                    isFirstCheck = false
                    debounceTask?.cancel()
                    await MainActor.run {
                        self.migrationState.phase = .idle
                    }
                    self.logger.info("Initial sync timeout, phase → .idle")
                }
            }

            // Keep listener alive indefinitely for continuous monitoring
            await withTaskCancellationHandler {
                // Keep listener reference alive
                _ = listener
                // Never timeout, keep monitoring until explicitly cancelled
                try? await Task.sleep(nanoseconds: .max)
            } onCancel: { [debounceTask] in
                debounceTask?.cancel()
                self.logger.info("CloudKit monitoring stopped")
            }
        }
    }
}

