//
//  MigrationState.swift
//  ExcalidrawZ
//
//  Created by Chocoford on 11/21/25.
//

import SwiftUI
import SwiftyAlert

enum MigrationPhase: Equatable {
    case idle
    case checking
    case migrating(name: String)
    case progress(description: String, value: Double)
    case completed
    case error(String)
    
    case closed
}

enum MigrationItemStatus: Equatable {
    case pending
    case checking
    case skipped
    case migrating(progress: Double, description: String)
    case completed
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
    @Environment(\.alertToast) private var alertToast

    @StateObject private var migrationState = MigrationState()
    @State private var showMigrationSheet = false

    let migrationManager = MigrationManager.shared

    #if DEBUG
    private let isDev = false
    #else
    private let isDev = false
    #endif

    func body(content: Content) -> some View {
        content
            .environmentObject(migrationState)
            .sheet(isPresented: $showMigrationSheet) {
                migrationState.phase = .closed
            } content: {
                MigrationProgressSheet(
                    migrationState: migrationState,
                    isDev: isDev,
                )
                .swiftyAlert()
            }
            .onAppear {
                if isDev {
                    showMigrationSheet = true
                }
                Task {
                    await checkMigrations()
                }
            }
    }

    private func checkMigrations() async {
        do {
            let needsMigration = try await migrationManager.checkMigrationsNeeded(state: migrationState)

            // Dev: always show sheet
            // Non-Dev: only show if migration is needed
            if isDev || needsMigration {
                showMigrationSheet = true
            }
        } catch {
            alertToast(error)
        }
    }
}
