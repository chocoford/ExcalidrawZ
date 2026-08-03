//
//  ExcalidrawMCPAppBridge.swift
//  ExcalidrawZ
//
//  Created by Codex on 6/15/26.
//

import CoreData
import Foundation
import SwiftUI

@MainActor
final class ExcalidrawMCPAppBridge {
    struct ApplyResult: Sendable {
        let targetFileID: String
        let preCheckpointID: UUID?
        let postCheckpointID: UUID?
        let checkpointWarning: String?
    }

    struct MutationCheckpointResult<Result>: Sendable where Result: Sendable {
        let result: Result
        let preCheckpointID: UUID?
        let postCheckpointID: UUID?
        let checkpointWarning: String?
    }

    struct CreateFileRequest: Sendable {
        let name: String?
        let groupID: String?
        let localFolderID: String?

        init(
            name: String?,
            groupID: String?,
            localFolderID: String? = nil
        ) {
            self.name = name
            self.groupID = groupID
            self.localFolderID = localFolderID
        }

        var hasExplicitTarget: Bool {
            name?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                || groupID?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                || localFolderID?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        }
    }

    private struct ApplyRequestKey: Hashable {
        let targetFileID: String
        let clientUpdateID: String
    }

    enum BridgeError: LocalizedError {
        case appContextUnavailable
        case targetGroupUnavailable
        case createdFileUnavailable
        case aiGenerationInProgress
        case canvasUnavailable
        case fileLoadTimedOut
        case unsupportedActiveFile(String)
        case currentFileAccessDenied
        case fileNotFound(String)
        case groupNotFound(String)
        case unsupportedTargetGroup(String)
        case localFolderNotFound(String)
        case localFileNotFound(String)
        case invalidCreateTarget(String)
        case invalidGeneratedFile(String)

        var errorDescription: String? {
            switch self {
                case .appContextUnavailable:
                    "ExcalidrawZ is not ready. Open the app window before using MCP drawing tools."
                case .targetGroupUnavailable:
                    "No library group is available for the MCP drawing."
                case .createdFileUnavailable:
                    "The new MCP drawing file could not be loaded from persistence."
                case .aiGenerationInProgress:
                    "ExcalidrawZ is generating another AI response. Stop it before using MCP drawing tools."
                case .canvasUnavailable:
                    "The Excalidraw canvas is not ready. Open a drawing window before using MCP drawing tools."
                case .fileLoadTimedOut:
                    "The MCP target file did not finish loading in ExcalidrawZ."
                case .unsupportedActiveFile(let reason):
                    "The current file cannot be modified by MCP: \(reason)"
                case .currentFileAccessDenied:
                    AIFileAccessStatusMessage.protectedContentAccessDenied
                case .fileNotFound(let id):
                    "File not found: \(id)"
                case .groupNotFound(let id):
                    "Group not found: \(id)"
                case .unsupportedTargetGroup(let reason):
                    "The requested group cannot be used for MCP file creation: \(reason)"
                case .localFolderNotFound(let id):
                    "Local folder not found or not accessible: \(id)"
                case .localFileNotFound(let id):
                    "Local file not found or not accessible: \(id)"
                case .invalidCreateTarget(let message):
                    "Invalid MCP file creation target: \(message)"
                case .invalidGeneratedFile(let message):
                    "The generated Excalidraw file is invalid: \(message)"
            }
        }
    }

    static let shared = ExcalidrawMCPAppBridge()

    private weak var fileState: FileState?
    private weak var context: NSManagedObjectContext?
    private var recentApplyResults: [ApplyRequestKey: ApplyResult] = [:]
    private var recentApplyResultKeys: [ApplyRequestKey] = []
    private static let maxRecentApplyResultCount = 32

    private init() {}

    func register(
        fileState: FileState,
        context: NSManagedObjectContext
    ) {
        self.fileState = fileState
        self.context = context
    }

    @discardableResult
    func createElements(
        _ elements: [MCPJSONValue]
    ) async throws -> [MCPJSONValue] {
        guard let coordinator = fileState?.excalidrawWebCoordinator else {
            throw BridgeError.canvasUnavailable
        }
        let inputData = try MCPJSONValue.array(elements).mcpJSONData()
        let inputElements = try JSONDecoder().decode(ExcalidrawCore.JSONValue.self, from: inputData)
        let convertedElements = try await coordinator.createElements(
            inputElements,
            options: .init(regenerateIds: false)
        )
        let convertedData = try JSONEncoder().encode(convertedElements)
        let convertedValue = try MCPJSONValue.parse(from: convertedData)
        guard let convertedArray = convertedValue.arrayValue else {
            throw BridgeError.invalidGeneratedFile("Converted elements is not a JSON array.")
        }
        return convertedArray
    }

    @discardableResult
    func apply(
        _ session: ExcalidrawMCPDiagramSession,
        clientUpdateID: String? = nil,
        createFileIfNeeded: CreateFileRequest? = nil
    ) async throws -> ApplyResult {
        guard let fileState else {
            throw BridgeError.appContextUnavailable
        }
        guard fileState.aiChatSession == nil else {
            throw BridgeError.aiGenerationInProgress
        }
        syncCoordinatorRegistry(fileState: fileState)

        if let createFileIfNeeded,
           fileState.currentActiveFile == nil || createFileIfNeeded.hasExplicitTarget {
            try await createTargetFileIfNeeded(createFileIfNeeded)
        }

        let targetFile = try await requireActiveFileForMCPUpdate(fileState: fileState)
        let applyRequestKey = applyRequestKey(
            targetFileID: targetFile.id,
            clientUpdateID: clientUpdateID
        )
        if let applyRequestKey,
           let cachedResult = recentApplyResults[applyRequestKey] {
            return cachedResult
        }

        let preCheckpointID = try await recordMCPCheckpoint(
            file: targetFile,
            fileState: fileState,
            source: .mcpPre,
            description: mcpCheckpointDescription(
                phase: "Before MCP update",
                clientUpdateID: clientUpdateID
            )
        )

        let sessionElementsJSON: String
        do {
            sessionElementsJSON = try elementsJSON(for: session)
        } catch {
            if let preCheckpointID {
                try? await deleteMCPCheckpoint(id: preCheckpointID, file: targetFile)
            }
            throw error
        }
        fileState.mcpCheckpointSuppressionDepth += 1
        defer {
            fileState.mcpCheckpointSuppressionDepth = max(
                0,
                fileState.mcpCheckpointSuppressionDepth - 1
            )
        }
        do {
            try await replaceCanvasElements(
                sessionElementsJSON,
                fileID: targetFile.id,
                fileState: fileState
            )
            try await applyViewportUpdate(
                session.viewportUpdate,
                fileID: targetFile.id,
                fileState: fileState
            )
        } catch {
            if let preCheckpointID {
                try? await deleteMCPCheckpoint(id: preCheckpointID, file: targetFile)
            }
            throw error
        }

        var checkpointWarning: String?
        let postCheckpointID: UUID?
        do {
            postCheckpointID = try await recordMCPCheckpoint(
                file: targetFile,
                fileState: fileState,
                source: .mcpPost,
                description: mcpCheckpointDescription(
                    phase: "MCP update",
                    clientUpdateID: clientUpdateID
                )
            )
        } catch {
            postCheckpointID = nil
            checkpointWarning = "MCP update succeeded, but post-update checkpoint failed: \(error.localizedDescription)"
        }

        let result = ApplyResult(
            targetFileID: targetFile.id,
            preCheckpointID: preCheckpointID,
            postCheckpointID: postCheckpointID,
            checkpointWarning: checkpointWarning
        )
        if let applyRequestKey {
            cacheApplyResult(result, for: applyRequestKey)
        }
        return result
    }

    func optimizedAppContext() async -> MCPJSONValue {
        guard let fileState else {
            return .object([
                "serviceMode": .string(ExcalidrawMCPServiceMode.optimized.rawValue),
                "app": appInfo(),
                "ready": .bool(false),
                "message": .string("ExcalidrawZ is not ready. Open the app window before using Optimized MCP.")
            ])
        }
        syncCoordinatorRegistry(fileState: fileState)

        let activeFile = fileState.currentActiveFile
        let allowsFileAccess = AIChatPreferences.shared.allowsFileAccess(for: activeFile)
        let lockedContentAllowsRead = await LockedContentAIGuard.canAIRead(activeFile: activeFile)
        let canReadCurrentFile = activeFile != nil && allowsFileAccess && lockedContentAllowsRead
        let canUpdateView = canUpdateView(
            activeFile: activeFile,
            canReadCurrentFile: canReadCurrentFile
        )
        let canvasTarget = canvasTarget(for: activeFile)
        let coordinator = ExcalidrawCoordinatorRegistry.shared.coordinator(for: canvasTarget)
        let canvasPreferences = await currentCanvasPreferencesValue(
            for: coordinator,
            canReadCurrentFile: canReadCurrentFile
        )
        let loadedFileID = coordinator?.documentSyncController.currentLoadedFileID
        let loadedFileMatchesCurrentFile = activeFile.map { $0.id == loadedFileID } ?? false
        let localFolder = await currentLocalFolder(for: activeFile)

        return .object([
            "serviceMode": .string(ExcalidrawMCPServiceMode.optimized.rawValue),
            "app": appInfo(),
            "ready": .bool(true),
            "currentFile": currentFileInfo(
                activeFile,
                allowsFileAccess: allowsFileAccess,
                lockedContentAllowsRead: lockedContentAllowsRead,
                canReadCurrentFile: canReadCurrentFile,
                canUpdateView: canUpdateView,
                activeGroup: fileState.currentActiveGroup,
                localFolder: localFolder
            ),
            "canvas": .object([
                "target": .string(canvasTarget.rawValue),
                "isReady": .bool(coordinator != nil && coordinator?.isLoading != true),
                "loadedFileId": optionalString(loadedFileMatchesCurrentFile ? loadedFileID : nil),
                "loadedFileMatchesCurrentFile": .bool(loadedFileMatchesCurrentFile),
                "preferences": canvasPreferences
            ])
        ])
    }

    func optimizedCurrentFile() async -> MCPJSONValue {
        guard let fileState else {
            return .object([
                "ready": .bool(false),
                "currentFile": .object([
                    "isOpen": .bool(false),
                    "canReadContent": .bool(false),
                    "canUpdateView": .bool(false),
                    "message": .string("ExcalidrawZ is not ready. Open the app window before using MCP drawing tools.")
                ])
            ])
        }
        syncCoordinatorRegistry(fileState: fileState)

        let activeFile = fileState.currentActiveFile
        let allowsFileAccess = AIChatPreferences.shared.allowsFileAccess(for: activeFile)
        let lockedContentAllowsRead = await LockedContentAIGuard.canAIRead(activeFile: activeFile)
        let canReadCurrentFile = activeFile != nil && allowsFileAccess && lockedContentAllowsRead
        let canUpdateView = canUpdateView(
            activeFile: activeFile,
            canReadCurrentFile: canReadCurrentFile
        )
        let canvasTarget = canvasTarget(for: activeFile)
        let coordinator = ExcalidrawCoordinatorRegistry.shared.coordinator(for: canvasTarget)
        let loadedFileID = coordinator?.documentSyncController.currentLoadedFileID
        let loadedFileMatchesCurrentFile = activeFile.map { $0.id == loadedFileID } ?? false
        let localFolder = await currentLocalFolder(for: activeFile)

        return .object([
            "ready": .bool(true),
            "currentFile": currentFileInfo(
                activeFile,
                allowsFileAccess: allowsFileAccess,
                lockedContentAllowsRead: lockedContentAllowsRead,
                canReadCurrentFile: canReadCurrentFile,
                canUpdateView: canUpdateView,
                activeGroup: fileState.currentActiveGroup,
                localFolder: localFolder
            ),
            "canvas": .object([
                "target": .string(canvasTarget.rawValue),
                "isReady": .bool(coordinator != nil && coordinator?.isLoading != true),
                "loadedFileId": optionalString(loadedFileMatchesCurrentFile ? loadedFileID : nil),
                "loadedFileMatchesCurrentFile": .bool(loadedFileMatchesCurrentFile)
            ])
        ])
    }

    func optimizedReadView(
        options: ExcalidrawMCPOptimizedToolHandler.CurrentCanvasOptions
    ) async throws -> MCPJSONValue {
        guard let fileState else {
            throw BridgeError.appContextUnavailable
        }
        syncCoordinatorRegistry(fileState: fileState)
        let activeFile = fileState.currentActiveFile
        try await ensureMCPCanAccessActiveFile(fileState.currentActiveFile)
        guard let data = try await CurrentExcalidrawDataResolver.resolve(
            fileState: fileState,
            canvasTarget: canvasTarget(for: activeFile)
        ) else {
            throw BridgeError.canvasUnavailable
        }

        let value = try MCPJSONValue.parse(from: data)
        guard case .object(var object) = value else {
            throw BridgeError.invalidGeneratedFile("Current canvas data is not a JSON object.")
        }

        if !options.includeElements {
            object.removeValue(forKey: "elements")
        }
        if !options.includeAppState {
            object.removeValue(forKey: "appState")
        }
        if !options.includeFiles {
            object.removeValue(forKey: "files")
        }
        let allowsFileAccess = AIChatPreferences.shared.allowsFileAccess(for: activeFile)
        let lockedContentAllowsRead = await LockedContentAIGuard.canAIRead(activeFile: activeFile)
        let canReadCurrentFile = activeFile != nil && allowsFileAccess && lockedContentAllowsRead
        let localFolder = await currentLocalFolder(for: activeFile)
        object["metadata"] = .object([
            "source": .string("ExcalidrawZ Optimized MCP"),
            "currentFile": currentFileInfo(
                activeFile,
                allowsFileAccess: allowsFileAccess,
                lockedContentAllowsRead: lockedContentAllowsRead,
                canReadCurrentFile: canReadCurrentFile,
                canUpdateView: canUpdateView(
                    activeFile: activeFile,
                    canReadCurrentFile: canReadCurrentFile
                ),
                activeGroup: fileState.currentActiveGroup,
                localFolder: localFolder
            )
        ])
        return .object(object)
    }

    func optimizedSetCanvasPreferences(_ update: CanvasPreferencesSnapshot) async throws -> MCPJSONValue {
        guard let fileState else {
            throw BridgeError.appContextUnavailable
        }
        syncCoordinatorRegistry(fileState: fileState)
        let targetFile = try await requireActiveFileForMCPUpdate(fileState: fileState)
        guard let coordinator = fileState.excalidrawWebCoordinator else {
            throw BridgeError.canvasUnavailable
        }
        try await waitForLoadedFile(targetFile.id, coordinator: coordinator)

        if update.isEmpty {
            return try canvasPreferencesResult(
                snapshot: await safeFetchCanvasPreferences(from: coordinator),
                checkpointStatus: "unchanged",
                warning: nil
            )
        }

        let preCheckpointID = try await recordMCPCheckpoint(
            file: targetFile,
            fileState: fileState,
            source: .mcpPre,
            description: "Before MCP canvas preference update"
        )

        fileState.mcpCheckpointSuppressionDepth += 1
        defer {
            fileState.mcpCheckpointSuppressionDepth = max(
                0,
                fileState.mcpCheckpointSuppressionDepth - 1
            )
        }
        do {
            try await coordinator.setCanvasPreferences(update)
        } catch {
            if let preCheckpointID {
                try? await deleteMCPCheckpoint(id: preCheckpointID, file: targetFile)
            }
            throw error
        }

        var warning: String?
        let postCheckpointID: UUID?
        do {
            postCheckpointID = try await recordMCPCheckpoint(
                file: targetFile,
                fileState: fileState,
                source: .mcpPost,
                description: "MCP canvas preference update"
            )
        } catch {
            postCheckpointID = nil
            warning = "Canvas preferences updated, but post-update checkpoint failed: \(error.localizedDescription)"
        }

        return try canvasPreferencesResult(
            snapshot: await safeFetchCanvasPreferences(from: coordinator),
            checkpointStatus: preCheckpointID != nil || postCheckpointID != nil ? "recorded" : "unavailable",
            warning: warning
        )
    }

    func optimizedMutationWithCheckpoints<Result: Sendable>(
        description: String,
        operation: () async throws -> Result
    ) async throws -> MutationCheckpointResult<Result> {
        guard let fileState else {
            throw BridgeError.appContextUnavailable
        }
        guard fileState.aiChatSession == nil else {
            throw BridgeError.aiGenerationInProgress
        }
        syncCoordinatorRegistry(fileState: fileState)
        let targetFile = try await requireActiveFileForMCPUpdate(fileState: fileState)
        let preCheckpointID = try await recordMCPCheckpoint(
            file: targetFile,
            fileState: fileState,
            source: .mcpPre,
            description: "Before \(description)"
        )

        fileState.mcpCheckpointSuppressionDepth += 1
        defer {
            fileState.mcpCheckpointSuppressionDepth = max(
                0,
                fileState.mcpCheckpointSuppressionDepth - 1
            )
        }
        let result: Result
        do {
            result = try await operation()
        } catch {
            if let preCheckpointID {
                try? await deleteMCPCheckpoint(id: preCheckpointID, file: targetFile)
            }
            throw error
        }

        var warning: String?
        let postCheckpointID: UUID?
        do {
            postCheckpointID = try await recordMCPCheckpoint(
                file: targetFile,
                fileState: fileState,
                source: .mcpPost,
                description: description
            )
        } catch {
            postCheckpointID = nil
            warning = "\(description) succeeded, but post-update checkpoint failed: \(error.localizedDescription)"
        }

        return MutationCheckpointResult(
            result: result,
            preCheckpointID: preCheckpointID,
            postCheckpointID: postCheckpointID,
            checkpointWarning: warning
        )
    }

    private func recordMCPCheckpoint(
        file: FileState.ActiveFile,
        fileState: FileState,
        source: FileCheckpointSource,
        description: String?
    ) async throws -> UUID? {
        switch file {
            case .file(let file):
                let content = try await currentSnapshotContent(
                    file: file,
                    fileState: fileState
                )
                return try await PersistenceController.shared.fileRepository.recordCheckpoint(
                    fileObjectID: file.objectID,
                    content: content,
                    source: source,
                    description: description
                )

            case .localFile(let url):
                let content = try await currentSnapshotContent(
                    localFileURL: url,
                    fileState: fileState
                )
                return try await recordLocalMCPCheckpoint(
                    url: url,
                    content: content,
                    source: source,
                    description: description
                )

            case .temporaryFile, .collaborationFile, .cloudStorageFile:
                return nil
        }
    }

    private func currentSnapshotContent(
        file: File,
        fileState: FileState
    ) async throws -> Data {
        if let liveContent = try await CurrentExcalidrawDataResolver.resolve(
            fileState: fileState,
            canvasTarget: canvasTarget(for: .file(file))
        ) {
            return liveContent
        }
        return try await file.loadContent()
    }

    private func currentSnapshotContent(
        localFileURL url: URL,
        fileState: FileState
    ) async throws -> Data {
        if let liveContent = try await CurrentExcalidrawDataResolver.resolve(
            fileState: fileState,
            canvasTarget: canvasTarget(for: .localFile(url))
        ) {
            return liveContent
        }
        return try await FileSyncCoordinator.shared.openFile(url)
    }

    private func recordLocalMCPCheckpoint(
        url: URL,
        content: Data,
        source: FileCheckpointSource,
        description: String?
    ) async throws -> UUID {
        let context = PersistenceController.shared.container.newBackgroundContext()
        return try await context.perform {
            let checkpoint = LocalFileCheckpoint(context: context)
            let checkpointID = UUID()
            checkpoint.id = checkpointID
            checkpoint.url = url
            checkpoint.content = content
            checkpoint.updatedAt = .now
            checkpoint.source = source.rawValue
            checkpoint.historyDescription = description
            context.insert(checkpoint)
            try context.save()
            return checkpointID
        }
    }

    private func deleteMCPCheckpoint(
        id: UUID,
        file: FileState.ActiveFile
    ) async throws {
        switch file {
            case .file(let file):
                guard let checkpointObjectID = try await fileCheckpointObjectID(
                    id: id,
                    fileObjectID: file.objectID
                ) else {
                    return
                }
                try await PersistenceController.shared.checkpointRepository.deleteCheckpoint(
                    checkpointObjectID: checkpointObjectID
                )

            case .localFile(let url):
                try await deleteLocalMCPCheckpoint(id: id, url: url)

            case .temporaryFile, .collaborationFile, .cloudStorageFile:
                break
        }
    }

    private func fileCheckpointObjectID(
        id: UUID,
        fileObjectID: NSManagedObjectID
    ) async throws -> NSManagedObjectID? {
        let context = PersistenceController.shared.newTaskContext()
        return try await context.perform {
            guard let file = context.object(with: fileObjectID) as? File else {
                return nil
            }
            let request = NSFetchRequest<FileCheckpoint>(entityName: "FileCheckpoint")
            request.predicate = NSPredicate(
                format: "file == %@ AND id == %@",
                file,
                id as CVarArg
            )
            request.fetchLimit = 1
            return try context.fetch(request).first?.objectID
        }
    }

    private func deleteLocalMCPCheckpoint(
        id: UUID,
        url: URL
    ) async throws {
        let context = PersistenceController.shared.container.newBackgroundContext()
        try await context.perform {
            let request: NSFetchRequest<LocalFileCheckpoint> = LocalFileCheckpoint.fetchRequest()
            request.predicate = NSPredicate(
                format: "url == %@ AND id == %@",
                url as CVarArg,
                id as CVarArg
            )
            request.fetchLimit = 1
            if let checkpoint = try context.fetch(request).first {
                context.delete(checkpoint)
                try context.save()
            }
        }
    }

    private func mcpCheckpointDescription(
        phase: String,
        clientUpdateID: String?
    ) -> String {
        guard let clientUpdateID,
              !clientUpdateID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return phase
        }
        return "\(phase) (\(clientUpdateID))"
    }

    private func applyRequestKey(
        targetFileID: String,
        clientUpdateID: String?
    ) -> ApplyRequestKey? {
        guard let clientUpdateID else { return nil }
        let trimmedClientUpdateID = clientUpdateID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedClientUpdateID.isEmpty else { return nil }
        return ApplyRequestKey(
            targetFileID: targetFileID,
            clientUpdateID: trimmedClientUpdateID
        )
    }

    private func cacheApplyResult(
        _ result: ApplyResult,
        for key: ApplyRequestKey
    ) {
        recentApplyResults[key] = result
        recentApplyResultKeys.removeAll { $0 == key }
        recentApplyResultKeys.append(key)

        while recentApplyResultKeys.count > Self.maxRecentApplyResultCount {
            let removedKey = recentApplyResultKeys.removeFirst()
            recentApplyResults.removeValue(forKey: removedKey)
        }
    }

    private func createTargetFileIfNeeded(_ request: CreateFileRequest) async throws {
        let localFolderID = request.localFolderID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let groupID = request.groupID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard localFolderID.isEmpty || groupID.isEmpty else {
            throw BridgeError.invalidCreateTarget("Use either group_id or local_folder_id, not both.")
        }

        if !localFolderID.isEmpty {
            _ = try await optimizedCreateLocalFile(
                name: request.name,
                localFolderID: localFolderID
            )
        } else {
            _ = try await optimizedCreateFile(
                name: request.name,
                groupID: request.groupID
            )
        }
    }

    func optimizedListGroups() async throws -> MCPJSONValue {
        guard let fileState else {
            throw BridgeError.appContextUnavailable
        }
        let currentGroupID: String? = {
            guard case .group(let group) = fileState.currentActiveGroup else {
                return nil
            }
            return group.id?.uuidString
        }()

        let context = PersistenceController.shared.newTaskContext()
        let groups = try await context.perform {
            let roots = try PersistenceController.shared.listGroups(context: context)
            var entries: [MCPJSONValue] = []

            func appendGroup(
                _ groupNode: PersistenceController.ExcalidrawGroup,
                depth: Int
            ) throws {
                let group = groupNode.group
                let groupType = group.groupType
                let pathComponents = (groupNode.ancestors + [group]).map {
                    $0.name ?? "Untitled"
                }
                let files = try PersistenceController.shared.listFiles(in: group, context: context)
                let id = group.id?.uuidString
                let parentID = group.parent?.id?.uuidString

                entries.append(.object([
                    "id": id.map(MCPJSONValue.string) ?? .null,
                    "name": group.name.map(MCPJSONValue.string) ?? .null,
                    "type": .string(groupType.rawValue),
                    "parent_id": parentID.map(MCPJSONValue.string) ?? .null,
                    "path": .array(pathComponents.map(MCPJSONValue.string)),
                    "depth": .number(Double(depth)),
                    "file_count": .number(Double(files.count)),
                    "children_count": .number(Double(groupNode.children.count)),
                    "can_create_file": .bool(groupType != .trash && id != nil),
                    "is_current": .bool(id == currentGroupID)
                ]))

                for child in groupNode.children {
                    try appendGroup(child, depth: depth + 1)
                }
            }

            for root in roots {
                try appendGroup(root, depth: 0)
            }
            return entries
        }

        return .object([
            "groups": .array(groups),
            "returned": .number(Double(groups.count)),
            "id_policy": .string("Pass a non-trash group id to create_file.group_id. Local folders are not included in this tool.")
        ])
    }

    func optimizedListLocalFolders() async throws -> MCPJSONValue {
        guard let fileState else {
            throw BridgeError.appContextUnavailable
        }
        let currentFolderID: String? = {
            guard case .localFolder(let folder) = fileState.currentActiveGroup else {
                return nil
            }
            return folder.objectID.uriRepresentation().absoluteString
        }()

        let context = PersistenceController.shared.newTaskContext()
        let folders = try await context.perform {
            let request = NSFetchRequest<LocalFolder>(entityName: "LocalFolder")
            request.sortDescriptors = [
                NSSortDescriptor(key: "rank", ascending: true),
                NSSortDescriptor(key: "filePath", ascending: true)
            ]
            let localFolders = try context.fetch(request)
            return localFolders.map { folder in
                let folderID = folder.objectID.uriRepresentation().absoluteString
                let pathComponents = Self.localFolderPathComponents(folder)
                let directFileCount = (try? folder.getFiles(deep: false).count) ?? 0
                let canCreateFile: Bool = {
                    switch folder.checkPathExists() {
                        case .success:
                            return true
                        case .failure:
                            return false
                    }
                }()
                return MCPJSONValue.object([
                    "local_folder_id": .string(folderID),
                    "name": .string(folder.url?.lastPathComponent ?? folder.filePath ?? "Untitled"),
                    "path": Self.optionalStringValue(folder.filePath),
                    "parent_local_folder_id": Self.optionalStringValue(
                        folder.parent?.objectID.uriRepresentation().absoluteString
                    ),
                    "path_components": .array(pathComponents.map(MCPJSONValue.string)),
                    "depth": .number(Double(pathComponents.count - 1)),
                    "direct_file_count": .number(Double(directFileCount)),
                    "can_create_file": .bool(canCreateFile),
                    "is_current": .bool(folderID == currentFolderID)
                ])
            }
        }

        return .object([
            "local_folders": .array(folders),
            "returned": .number(Double(folders.count)),
            "id_policy": .string("Pass local_folder_id to list_local_files or create_local_file.")
        ])
    }

    func optimizedListLocalFiles(
        folderID rawFolderID: String?,
        deep: Bool = true,
        limit: Int = 100
    ) async throws -> MCPJSONValue {
        guard fileState != nil else {
            throw BridgeError.appContextUnavailable
        }
        let cappedLimit = min(max(limit, 1), 200)
        let context = PersistenceController.shared.newTaskContext()

        let files = try await context.perform {
            let folders: [LocalFolder]
            if let rawFolderID,
               !rawFolderID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                folders = [try Self.localFolder(from: rawFolderID, context: context)]
            } else {
                let request = NSFetchRequest<LocalFolder>(entityName: "LocalFolder")
                request.sortDescriptors = [
                    NSSortDescriptor(key: "rank", ascending: true),
                    NSSortDescriptor(key: "filePath", ascending: true)
                ]
                folders = try context.fetch(request)
            }

            var seenPaths = Set<String>()
            var entries: [MCPJSONValue] = []
            for folder in folders where entries.count < cappedLimit {
                let folderID = folder.objectID.uriRepresentation().absoluteString
                let folderPathComponents = Self.localFolderPathComponents(folder)
                let urls = (try? folder.getFiles(deep: deep)) ?? []
                for url in urls where entries.count < cappedLimit {
                    let standardizedURL = url.standardizedFileURL
                    let path = standardizedURL.path
                    guard seenPaths.insert(path).inserted else { continue }
                    let resourceValues = try? standardizedURL.resourceValues(
                        forKeys: [.contentModificationDateKey, .fileSizeKey]
                    )
                    entries.append(.object([
                        "file_url": .string(standardizedURL.absoluteString),
                        "path": .string(path),
                        "name": .string(standardizedURL.lastPathComponent),
                        "local_folder_id": .string(folderID),
                        "local_folder_path": Self.optionalStringValue(folder.filePath),
                        "local_folder_path_components": .array(folderPathComponents.map(MCPJSONValue.string)),
                        "updated_at": Self.optionalStringValue(resourceValues?.contentModificationDate.map(Self.iso8601String(from:))),
                        "size_bytes": resourceValues?.fileSize.map { .number(Double($0)) } ?? .null
                    ]))
                }
            }
            return entries
        }

        return .object([
            "files": .array(files),
            "returned": .number(Double(files.count)),
            "limit": .number(Double(cappedLimit)),
            "deep": .bool(deep),
            "id_policy": .string("Pass file_url to open_local_file. Only files inside registered local folders are returned.")
        ])
    }

    func optimizedCreateFile(
        name rawName: String?,
        groupID rawGroupID: String? = nil
    ) async throws -> MCPJSONValue {
        guard let fileState,
              let context
        else {
            throw BridgeError.appContextUnavailable
        }
        guard fileState.aiChatSession == nil else {
            throw BridgeError.aiGenerationInProgress
        }
        let targetGroupID = try targetGroupID(
            fileState: fileState,
            context: context,
            requestedGroupID: rawGroupID
        )
        guard let content = ExcalidrawFile().content else {
            throw BridgeError.invalidGeneratedFile("Unable to create an empty Excalidraw file.")
        }
        let name = {
            let trimmed = rawName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return trimmed.isEmpty ? String(localizable: .mcpGeneratedFileName) : trimmed
        }()
        let fileObjectID = try await PersistenceController.shared.fileRepository.createFile(
            name: name,
            content: content,
            groupObjectID: targetGroupID
        )

        guard let file = context.object(with: fileObjectID) as? File else {
            throw BridgeError.createdFileUnavailable
        }
        if let group = file.group {
            fileState.currentActiveGroup = .group(group)
        }

        let activeFile = FileState.ActiveFile.file(file)
        guard await fileState.requestActiveFileChange(activeFile) else {
            throw BridgeError.aiGenerationInProgress
        }
        return currentFileInfo(
            activeFile,
            allowsFileAccess: true,
            lockedContentAllowsRead: true,
            canReadCurrentFile: true,
            canUpdateView: true,
            activeGroup: fileState.currentActiveGroup
        )
    }

    func optimizedCreateLocalFile(
        name rawName: String?,
        localFolderID rawLocalFolderID: String
    ) async throws -> MCPJSONValue {
        guard let fileState,
              let context
        else {
            throw BridgeError.appContextUnavailable
        }
        guard fileState.aiChatSession == nil else {
            throw BridgeError.aiGenerationInProgress
        }
        let folder = try Self.localFolder(from: rawLocalFolderID, context: context)
        guard let content = ExcalidrawFile().content else {
            throw BridgeError.invalidGeneratedFile("Unable to create an empty Excalidraw file.")
        }

        let fileURL = try await folder.withSecurityScopedURL { scopedURL in
            let url = try Self.uniqueLocalExcalidrawFileURL(
                in: scopedURL,
                requestedName: rawName
            )
            try await FileCoordinator.shared.coordinatedWrite(url: url, data: content)
            return url.standardizedFileURL
        }

        fileState.currentActiveGroup = .localFolder(folder)
        let activeFile = FileState.ActiveFile.localFile(fileURL)
        guard await fileState.requestActiveFileChange(activeFile) else {
            throw BridgeError.aiGenerationInProgress
        }
        return currentFileInfo(
            activeFile,
            allowsFileAccess: true,
            lockedContentAllowsRead: true,
            canReadCurrentFile: true,
            canUpdateView: true,
            activeGroup: fileState.currentActiveGroup,
            localFolder: folder
        )
    }

    func optimizedOpenFile(fileID rawFileID: String) async throws -> MCPJSONValue {
        guard let fileState,
              let context
        else {
            throw BridgeError.appContextUnavailable
        }
        guard fileState.aiChatSession == nil else {
            throw BridgeError.aiGenerationInProgress
        }
        guard let fileID = UUID(uuidString: rawFileID) else {
            throw BridgeError.fileNotFound(rawFileID)
        }

        let fileObjectID = try await libraryFileObjectID(fileID: fileID, includeTrash: false)
        guard try await LockedContentAIGuard.canToolAccess(fileObjectID: fileObjectID) else {
            throw BridgeError.currentFileAccessDenied
        }
        guard let file = context.object(with: fileObjectID) as? File else {
            throw BridgeError.fileNotFound(rawFileID)
        }
        if let group = file.group {
            fileState.currentActiveGroup = .group(group)
        }

        let activeFile = FileState.ActiveFile.file(file)
        guard await fileState.requestActiveFileChange(activeFile) else {
            throw BridgeError.aiGenerationInProgress
        }
        return currentFileInfo(
            activeFile,
            allowsFileAccess: true,
            lockedContentAllowsRead: true,
            canReadCurrentFile: true,
            canUpdateView: true,
            activeGroup: fileState.currentActiveGroup
        )
    }

    func optimizedOpenLocalFile(fileURL rawFileURL: String) async throws -> MCPJSONValue {
        guard let fileState else {
            throw BridgeError.appContextUnavailable
        }
        guard fileState.aiChatSession == nil else {
            throw BridgeError.aiGenerationInProgress
        }
        let fileURL = try Self.localFileURL(from: rawFileURL)
        let containingFolderID = try await localFolderObjectID(containing: fileURL)

        try await LocalFolder.withSecurityScopedAccessToContainingFolder(for: fileURL) {
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: fileURL.path, isDirectory: &isDirectory),
                  !isDirectory.boolValue,
                  fileURL.pathExtension.lowercased() == "excalidraw" else {
                throw BridgeError.localFileNotFound(rawFileURL)
            }
        }

        let containingFolder: LocalFolder? = {
            guard let context else { return nil }
            return try? context.existingObject(with: containingFolderID) as? LocalFolder
        }()

        if let folder = containingFolder {
            fileState.currentActiveGroup = .localFolder(folder)
        }

        let activeFile = FileState.ActiveFile.localFile(fileURL)
        guard await fileState.requestActiveFileChange(activeFile) else {
            throw BridgeError.aiGenerationInProgress
        }
        return currentFileInfo(
            activeFile,
            allowsFileAccess: true,
            lockedContentAllowsRead: true,
            canReadCurrentFile: true,
            canUpdateView: true,
            activeGroup: fileState.currentActiveGroup,
            localFolder: containingFolder
        )
    }

    private func requireActiveFileForMCPUpdate(
        fileState: FileState
    ) async throws -> FileState.ActiveFile {
        guard let activeFile = fileState.currentActiveFile else {
            throw BridgeError.unsupportedActiveFile(
                "no file is open. Call list_files and open_file, or call create_file, before replace_view."
            )
        }
        try validateMCPWritableActiveFile(activeFile, fileState: fileState)
        try await ensureMCPCanAccessActiveFile(activeFile)
        return activeFile
    }

    private func validateMCPWritableActiveFile(
        _ activeFile: FileState.ActiveFile,
        fileState: FileState
    ) throws {
        guard !fileState.currentActiveFileIsInTrash else {
            throw BridgeError.unsupportedActiveFile("file is in Trash.")
        }

        switch activeFile {
            case .file, .localFile, .temporaryFile, .cloudStorageFile:
                return
            case .collaborationFile:
                throw BridgeError.unsupportedActiveFile("collaboration files are not supported yet.")
        }
    }

    private func targetGroupID(
        fileState: FileState,
        context: NSManagedObjectContext,
        requestedGroupID: String? = nil
    ) throws -> NSManagedObjectID {
        let trimmedGroupID = requestedGroupID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmedGroupID.isEmpty {
            guard let groupID = UUID(uuidString: trimmedGroupID) else {
                throw BridgeError.groupNotFound(trimmedGroupID)
            }
            let request = NSFetchRequest<Group>(entityName: "Group")
            request.predicate = NSPredicate(format: "id == %@", groupID as CVarArg)
            request.fetchLimit = 1
            guard let group = try context.fetch(request).first else {
                throw BridgeError.groupNotFound(trimmedGroupID)
            }
            guard group.groupType != .trash else {
                throw BridgeError.unsupportedTargetGroup("Trash cannot receive new MCP files.")
            }
            return group.objectID
        }

        if case .group(let group) = fileState.currentActiveGroup,
           group.groupType != .trash {
            return group.objectID
        }

        guard let defaultGroup = try PersistenceController.shared.getDefaultGroup(context: context) else {
            throw BridgeError.targetGroupUnavailable
        }

        return defaultGroup.objectID
    }

    private nonisolated static func localFolder(
        from rawLocalFolderID: String,
        context: NSManagedObjectContext
    ) throws -> LocalFolder {
        let trimmed = rawLocalFolderID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let uri = URL(string: trimmed),
              let objectID = PersistenceController.shared.container
                .persistentStoreCoordinator
                .managedObjectID(forURIRepresentation: uri),
              let folder = try context.existingObject(with: objectID) as? LocalFolder else {
            throw BridgeError.localFolderNotFound(trimmed)
        }
        return folder
    }

    private func localFolderObjectID(containing fileURL: URL) async throws -> NSManagedObjectID {
        let filePath = fileURL.standardizedFileURL.path
        let context = PersistenceController.shared.newTaskContext()
        return try await context.perform {
            let request = NSFetchRequest<LocalFolder>(entityName: "LocalFolder")
            let folders = try context.fetch(request)
            guard let match = folders.compactMap({ folder -> (path: String, objectID: NSManagedObjectID)? in
                guard let folderPath = folder.filePath else { return nil }
                let standardizedFolderPath = URL(fileURLWithPath: folderPath).standardizedFileURL.path
                guard Self.filePath(filePath, isContainedInFolderPath: standardizedFolderPath) else {
                    return nil
                }
                return (standardizedFolderPath, folder.objectID)
            })
            .max(by: { $0.path.count < $1.path.count }) else {
                throw BridgeError.localFileNotFound(fileURL.absoluteString)
            }
            return match.objectID
        }
    }

    private nonisolated static func localFileURL(from rawFileURL: String) throws -> URL {
        let trimmed = rawFileURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let url: URL?
        if let parsed = URL(string: trimmed), parsed.isFileURL {
            url = parsed
        } else if trimmed.hasPrefix("/") {
            url = URL(fileURLWithPath: trimmed)
        } else {
            url = nil
        }
        guard let url else {
            throw BridgeError.localFileNotFound(trimmed)
        }
        return url.standardizedFileURL
    }

    private nonisolated static func uniqueLocalExcalidrawFileURL(
        in folderURL: URL,
        requestedName: String?
    ) throws -> URL {
        let baseName = normalizedLocalFileBaseName(requestedName)
        var candidate = folderURL.appendingPathComponent(baseName).appendingPathExtension("excalidraw")
        var index = 1
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = folderURL
                .appendingPathComponent("\(baseName)-\(index)")
                .appendingPathExtension("excalidraw")
            index += 1
        }
        return candidate
    }

    private nonisolated static func normalizedLocalFileBaseName(_ rawName: String?) -> String {
        var name = rawName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if name.lowercased().hasSuffix(".excalidraw") {
            name = String(name.dropLast(".excalidraw".count))
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let invalidCharacters = CharacterSet(charactersIn: "/:")
        name = name
            .components(separatedBy: invalidCharacters)
            .joined(separator: "-")
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ".")))
        return name.isEmpty ? "Untitled" : name
    }

    private nonisolated static func optionalStringValue(_ value: String?) -> MCPJSONValue {
        value.map(MCPJSONValue.string) ?? .null
    }

    private nonisolated static func groupPathComponents(_ group: Group?) -> [String] {
        var current = group
        var components: [String] = []
        while let group = current {
            components.insert(group.name ?? "Untitled", at: 0)
            current = group.parent
        }
        return components
    }

    private nonisolated static func localFolderPathComponents(_ folder: LocalFolder) -> [String] {
        var current: LocalFolder? = folder
        var components: [String] = []
        while let folder = current {
            components.insert(folder.url?.lastPathComponent ?? folder.filePath ?? "Untitled", at: 0)
            current = folder.parent
        }
        return components
    }

    private nonisolated static func filePath(
        _ filePath: String,
        isContainedInFolderPath folderPath: String
    ) -> Bool {
        filePath == folderPath || filePath.hasPrefix(folderPath + "/")
    }

    private func libraryFileObjectID(
        fileID: UUID,
        includeTrash: Bool
    ) async throws -> NSManagedObjectID {
        let context = PersistenceController.shared.newTaskContext()
        return try await context.perform {
            let fetchRequest = NSFetchRequest<File>(entityName: "File")
            if includeTrash {
                fetchRequest.predicate = NSPredicate(format: "id == %@", fileID as CVarArg)
            } else {
                fetchRequest.predicate = NSPredicate(
                    format: "id == %@ AND (inTrash == NO OR inTrash == nil)",
                    fileID as CVarArg
                )
            }
            fetchRequest.fetchLimit = 1
            guard let file = try context.fetch(fetchRequest).first else {
                throw BridgeError.fileNotFound(fileID.uuidString)
            }
            return file.objectID
        }
    }

    private func elementsJSON(for session: ExcalidrawMCPDiagramSession) throws -> String {
        let elementsData = try MCPJSONValue.array(session.elements).mcpJSONData()
        guard (try JSONSerialization.jsonObject(with: elementsData)) is [Any] else {
            throw BridgeError.invalidGeneratedFile("elements is not a JSON array.")
        }
        guard let jsonString = String(data: elementsData, encoding: .utf8) else {
            throw BridgeError.invalidGeneratedFile("elements JSON is not valid UTF-8.")
        }
        return jsonString
    }

    private func replaceCanvasElements(
        _ elementsJSON: String,
        fileID: String,
        fileState: FileState
    ) async throws {
        guard let coordinator = fileState.excalidrawWebCoordinator else {
            throw BridgeError.canvasUnavailable
        }

        try await waitForLoadedFile(fileID, coordinator: coordinator)
        try await coordinator.replaceAllElements(rawElementsJSON: elementsJSON)
    }

    private func applyViewportUpdate(
        _ viewportUpdate: ExcalidrawMCPUpstreamViewportUpdate?,
        fileID: String,
        fileState: FileState
    ) async throws {
        guard let viewportUpdate else { return }
        guard let coordinator = fileState.excalidrawWebCoordinator else {
            throw BridgeError.canvasUnavailable
        }

        try await waitForLoadedFile(fileID, coordinator: coordinator)
        _ = try await coordinator.setViewportFrame(.init(
            x: viewportUpdate.x,
            y: viewportUpdate.y,
            width: viewportUpdate.width,
            height: viewportUpdate.height
        ))
    }

    private func waitForLoadedFile(
        _ fileID: String,
        coordinator: ExcalidrawCanvasView.Coordinator
    ) async throws {
        let deadline = Date().addingTimeInterval(5)
        while coordinator.documentSyncController.currentLoadedFileID != fileID {
            if Date() >= deadline {
                throw BridgeError.fileLoadTimedOut
            }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
    }

    func ensureOptimizedRawUpdateAllowed() async throws {
        guard let fileState else {
            throw BridgeError.appContextUnavailable
        }
        guard fileState.aiChatSession == nil else {
            throw BridgeError.aiGenerationInProgress
        }
        if let activeFile = fileState.currentActiveFile {
            try validateMCPWritableActiveFile(activeFile, fileState: fileState)
        }
        try await ensureMCPCanAccessActiveFile(fileState.currentActiveFile)
    }

    func ensureOptimizedUpdateViewAllowed() async throws {
        guard let fileState else {
            throw BridgeError.appContextUnavailable
        }
        guard fileState.aiChatSession == nil else {
            throw BridgeError.aiGenerationInProgress
        }
        _ = try await requireActiveFileForMCPUpdate(fileState: fileState)
    }

    private func ensureMCPCanAccessActiveFile(_ activeFile: FileState.ActiveFile?) async throws {
        guard let activeFile else { return }
        guard AIChatPreferences.shared.allowsFileAccess(for: activeFile),
              await LockedContentAIGuard.canAIRead(activeFile: activeFile) else {
            throw BridgeError.currentFileAccessDenied
        }
    }

    func optimizedActiveCheckpointTargetArguments() async throws -> [String: MCPJSONValue] {
        guard let fileState else {
            throw BridgeError.appContextUnavailable
        }
        try await ensureMCPCanAccessActiveFile(fileState.currentActiveFile)

        switch fileState.currentActiveFile {
            case .file(let file):
                guard let id = file.id?.uuidString else {
                    throw BridgeError.fileNotFound("active file")
                }
                return ["file_id": .string(id)]
            case .localFile(let url):
                return ["file_url": .string(url.standardizedFileURL.absoluteString)]
            case .temporaryFile:
                throw BridgeError.unsupportedActiveFile(
                    "get_current_file_checkpoints requires an active library file or active local file."
                )
            case .collaborationFile:
                throw BridgeError.unsupportedActiveFile("collaboration files are not supported yet.")
            case .cloudStorageFile:
                throw BridgeError.unsupportedActiveFile(
                    "get_current_file_checkpoints does not support cloud storage files yet."
                )
            case nil:
                throw BridgeError.unsupportedActiveFile(
                    "get_current_file_checkpoints requires an active library file or active local file."
                )
        }
    }

    func optimizedChatToolContext(
        requiresMutation: Bool,
        requiresActiveFile: Bool = false
    ) async throws -> ExcalidrawChatInvocationContext {
        guard let fileState else {
            throw BridgeError.appContextUnavailable
        }
        syncCoordinatorRegistry(fileState: fileState)
        let activeFile = fileState.currentActiveFile
        if requiresActiveFile, activeFile == nil {
            throw BridgeError.unsupportedActiveFile(
                "no file is open. Call list_files and open_file, or call create_file, before this tool."
            )
        }
        if requiresMutation {
            try await ensureOptimizedRawUpdateAllowed()
        } else {
            try await ensureMCPCanAccessActiveFile(fileState.currentActiveFile)
        }

        let currentFileID: UUID? = {
            if case .file(let file) = activeFile {
                return file.id
            }
            return nil
        }()
        let canvasTarget = canvasTarget(for: activeFile)
        let currentFileData: Data? = if activeFile != nil {
            try await CurrentExcalidrawDataResolver.resolve(
                fileState: fileState,
                canvasTarget: canvasTarget
            )
        } else {
            nil
        }

        return ExcalidrawChatInvocationContext(
            currentFileData: currentFileData,
            canvasTarget: canvasTarget,
            readCanvasTarget: canvasTarget,
            currentFileID: currentFileID,
            hasActiveFile: activeFile != nil
        )
    }

    func optimizedFileAccessStatusContext() async -> ExcalidrawChatInvocationContext {
        guard let fileState else {
            return ExcalidrawChatInvocationContext(
                currentFileData: nil,
                canvasTarget: .normal,
                readCanvasTarget: .normal,
                hasActiveFile: false,
                isCurrentFileContextProtected: false
            )
        }

        let activeFile = fileState.currentActiveFile
        let currentFileID: UUID? = {
            if case .file(let file) = activeFile {
                return file.id
            }
            return nil
        }()
        let allowsFileAccess = AIChatPreferences.shared.allowsFileAccess(for: activeFile)
        let lockedContentAllowsRead = await LockedContentAIGuard.canAIRead(activeFile: activeFile)
        let isProtected = activeFile != nil && !(allowsFileAccess && lockedContentAllowsRead)
        let canvasTarget = canvasTarget(for: activeFile)

        return ExcalidrawChatInvocationContext(
            currentFileData: nil,
            canvasTarget: canvasTarget,
            readCanvasTarget: canvasTarget,
            currentFileID: currentFileID,
            hasActiveFile: activeFile != nil,
            isCurrentFileContextProtected: isProtected
        )
    }

    private func syncCoordinatorRegistry(fileState: FileState) {
        ExcalidrawCoordinatorRegistry.shared.update(
            normal: fileState.excalidrawWebCoordinator,
            collaboration: fileState.excalidrawCollaborationWebCoordinator
        )
    }

    private func canvasTarget(
        for activeFile: FileState.ActiveFile?
    ) -> ExcalidrawCoordinatorRegistry.CanvasTarget {
        switch activeFile {
            case .collaborationFile:
                .collaboration
            default:
                .normal
        }
    }

    private func canUpdateView(
        activeFile: FileState.ActiveFile?,
        canReadCurrentFile: Bool
    ) -> Bool {
        guard let activeFile else { return false }
        guard canReadCurrentFile, !activeFile.isInTrash else { return false }
        if case .collaborationFile = activeFile {
            return false
        }
        return true
    }

    private func appInfo() -> MCPJSONValue {
        .object([
            "name": .string("ExcalidrawZ"),
            "version": .string(Bundle.main.object(
                forInfoDictionaryKey: "CFBundleShortVersionString"
            ) as? String ?? "0")
        ])
    }

    private func currentFileInfo(
        _ activeFile: FileState.ActiveFile?,
        allowsFileAccess: Bool,
        lockedContentAllowsRead: Bool,
        canReadCurrentFile: Bool,
        canUpdateView: Bool,
        activeGroup: FileState.ActiveGroup? = nil,
        localFolder: LocalFolder? = nil
    ) -> MCPJSONValue {
        guard let activeFile else {
            return .object([
                "isOpen": .bool(false),
                "canReadContent": .bool(false),
                "canUpdateView": .bool(false),
                "message": .string("No file is currently open. Call list_files/open_file, list_local_files/open_local_file, create_file, or create_local_file before replace_view.")
            ])
        }

        var fileInfo: [String: MCPJSONValue] = [
            "isOpen": .bool(true),
            "id": .string(activeFile.id),
            "name": optionalString(activeFile.name),
            "kind": .string(activeFileKind(activeFile)),
            "fileType": .string(activeFile.fileType.identifier),
            "updatedAt": optionalString(activeFile.updatedAt.map { Self.iso8601String(from: $0) }),
            "isInTrash": .bool(activeFile.isInTrash),
            "allowsFileAccess": .bool(allowsFileAccess),
            "lockedContentAllowsRead": .bool(lockedContentAllowsRead),
            "canReadContent": .bool(canReadCurrentFile),
            "canUpdateView": .bool(canUpdateView)
        ]
        if case .file(let file) = activeFile {
            let groupPath = Self.groupPathComponents(file.group)
            fileInfo["group_id"] = optionalString(file.group?.id?.uuidString)
            fileInfo["group"] = optionalString(file.group?.name)
            fileInfo["group_path"] = .array(groupPath.map(MCPJSONValue.string))
            fileInfo["group_type"] = optionalString(file.group?.groupType.rawValue)
        }
        if case .localFile(let url) = activeFile {
            let standardizedURL = url.standardizedFileURL
            fileInfo["file_url"] = .string(standardizedURL.absoluteString)
            fileInfo["path"] = .string(standardizedURL.path)
            let folder = localFolder ?? {
                guard case .localFolder(let folder) = activeGroup else { return nil }
                return folder
            }()
            if let folder {
                fileInfo["local_folder_id"] = .string(folder.objectID.uriRepresentation().absoluteString)
                fileInfo["local_folder_path"] = Self.optionalStringValue(folder.filePath)
                fileInfo["local_folder_path_components"] = .array(
                    Self.localFolderPathComponents(folder).map(MCPJSONValue.string)
                )
            }
        }
        return .object(fileInfo)
    }

    private func currentLocalFolder(for activeFile: FileState.ActiveFile?) async -> LocalFolder? {
        guard case .localFile(let url) = activeFile else {
            return nil
        }
        let filePath = url.standardizedFileURL.path
        if case .localFolder(let folder) = fileState?.currentActiveGroup,
           let folderPath = folder.filePath,
           Self.filePath(
               filePath,
               isContainedInFolderPath: URL(fileURLWithPath: folderPath).standardizedFileURL.path
           ) {
            return folder
        }
        guard let context,
              let objectID = try? await localFolderObjectID(containing: url) else {
            return nil
        }
        return try? context.existingObject(with: objectID) as? LocalFolder
    }

    private func currentCanvasPreferencesValue(
        for coordinator: ExcalidrawCore?,
        canReadCurrentFile: Bool
    ) async -> MCPJSONValue {
        guard canReadCurrentFile,
              let coordinator,
              coordinator.isLoading != true,
              let snapshot = try? await coordinator.fetchCanvasPreferences(),
              let value = try? mcpJSONValue(from: snapshot) else {
            return .null
        }
        return value
    }

    private func safeFetchCanvasPreferences(
        from coordinator: ExcalidrawCore
    ) async -> CanvasPreferencesSnapshot? {
        do {
            return try await coordinator.fetchCanvasPreferences()
        } catch {
            return nil
        }
    }

    private func canvasPreferencesResult(
        snapshot: CanvasPreferencesSnapshot?,
        checkpointStatus: String,
        warning: String?
    ) throws -> MCPJSONValue {
        let message = checkpointStatus == "unchanged"
            ? "Canvas preferences unchanged."
            : "Canvas preferences updated."
        var object: [String: MCPJSONValue] = [
            "message": .string(message),
            "appFileHistoryCheckpointStatus": .string(checkpointStatus),
            "canvasPreferences": .null
        ]
        if let snapshot {
            object["canvasPreferences"] = try mcpJSONValue(from: snapshot)
        }
        if let warning {
            object["appCheckpointWarning"] = .string(warning)
        }
        return .object(object)
    }

    private func mcpJSONValue<T: Encodable>(from value: T) throws -> MCPJSONValue {
        try MCPJSONValue.parse(from: value.mcpJSONData())
    }

    private func activeFileKind(_ activeFile: FileState.ActiveFile) -> String {
        switch activeFile {
            case .file:
                return "libraryFile"
            case .localFile:
                return "localFile"
            case .temporaryFile:
                return "temporaryFile"
            case .collaborationFile:
                return "collaborationFile"
            case .cloudStorageFile:
                return "cloudStorageFile"
        }
    }

    private func optionalString(_ value: String?) -> MCPJSONValue {
        value.map(MCPJSONValue.string) ?? .null
    }

}

private extension ExcalidrawMCPAppBridge {
    nonisolated static func iso8601String(from date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }
}
