//
//  MigrationManager.swift
//  ExcalidrawZ
//
//  Created by ChatGPT on 2025.
//

import Foundation
import CoreData
import Logging

protocol MigrationVersion {
    static var name: String { get }
    static var description: String { get }
    
    var context: NSManagedObjectContext { get }
    
    init(context: NSManagedObjectContext)
    
    func checkIfShouldMigrate() async throws -> Bool
    func migrate(
        progressHandler: @escaping (_ description: String, _ progress: Double) async -> Void
    ) async throws
}


actor MigrationManager {
    static let shared = MigrationManager()
    let logger = Logger(label: "MigrationManager")

    private init() {}

    static var migrations: [any MigrationVersion.Type] = [
        Migration_ExtractMediaItems.self,
        Migration_MoveContentToICloudDrive.self,
    ]

    /// Check if any migrations are needed without running them.
    /// Marks the first migration that needs to run and all subsequent ones as pending.
    func checkMigrationsNeeded(state: MigrationState) async throws -> Bool {
        do {
            let context = PersistenceController.shared.newTaskContext()
            
            // Initialize all migrations
            await MainActor.run {
                state.initializeMigrations(Self.migrations)
                state.phase = .checking
            }
            
            for (index, migrationType) in Self.migrations.enumerated() {
                let name = migrationType.name
                let migration = migrationType.init(context: context)
                
                // Update to checking status
                await MainActor.run {
                    state.updateMigrationStatus(name: name, status: .checking)
                }
                
                if try await migration.checkIfShouldMigrate() {
                    // Found first migration that needs to run
                    // Mark this and all subsequent migrations as pending
                    await MainActor.run {
                        for i in index..<Self.migrations.count {
                            let pendingName = Self.migrations[i].name
                            state.updateMigrationStatus(name: pendingName, status: .pending)
                        }
                        state.phase = .idle
                    }
                    return true
                } else {
                    // Skip this migration
                    await MainActor.run {
                        state.updateMigrationStatus(name: name, status: .skipped)
                    }
                }
            }
            
            // No migrations needed
            await MainActor.run {
                state.phase = .closed
            }
            return false
        } catch {
            print(error)
            throw error
        }
    }

    /// Run migrations starting from pending items.
    func runPendingMigrations(state: MigrationState) async throws {
        let context = PersistenceController.shared.newTaskContext()
        
        for migrationType in Self.migrations {
            let name = migrationType.name
            
            // Get current status
            let currentStatus = await MainActor.run {
                state.migrations.first(where: { $0.name == name })?.status
            }
            
            let shouldRunMigration = {
                if case .failed = currentStatus {
                    return true
                }
                if case .pending = currentStatus {
                    return true
                }
                return false
            }()
            guard shouldRunMigration else {
                continue
            }
            
            let migration = migrationType.init(context: context)
            
            do {
                // Check again if migration is needed
                if try await migration.checkIfShouldMigrate() {
                    await MainActor.run {
                        state.phase = .migrating(name: name)
                        state.updateMigrationStatus(name: name, status: .migrating(progress: 0, description: "Starting..."))
                    }
                    
                    try await migration.migrate { description, progress in
                        await MainActor.run {
                            state.phase = .progress(description: description, value: progress)
                            state.updateMigrationStatus(name: name, status: .migrating(progress: progress, description: description))
                        }
                    }
                    
                    await MainActor.run {
                        state.updateMigrationStatus(name: name, status: .completed)
                    }
                } else {
                    // If no longer needs migration, mark as completed (not skipped)
                    await MainActor.run {
                        state.updateMigrationStatus(name: name, status: .completed)
                    }
                }
            } catch {
                await MainActor.run {
                    state.phase = .error(error.localizedDescription)
                    state.updateMigrationStatus(
                        name: name,
                        status: .failed(
                            error: error.localizedDescription,
                            progress: state.getMigrationProgress(name: name) ?? 0
                        )
                    )
                }
                throw error
            }
        }
        
        await MainActor.run {
            state.phase = .completed
        }
    }
}
