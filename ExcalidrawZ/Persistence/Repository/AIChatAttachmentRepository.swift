//
//  AIChatAttachmentRepository.swift
//  ExcalidrawZ
//
//  Domain-specific façade for AI chat attachments. Owns:
//
//  - The boundary translation between LLMCore's `ChatMessageContent.File`
//    (a value type with two cases — http URL or base64 data URI) and
//    our `PersistedFile` (the JSON-serializable record stored in the
//    `AIConversationMessage.filesData` column).
//  - The path-namespacing convention: every attachment lives under
//    `AIChatAttachments/<conversationID>/<UUID>.<ext>` so deleting a
//    conversation reduces to deleting one subdirectory and GC can
//    cross-reference per conversation cheaply.
//  - File lifecycle: cleanup on conversation delete, periodic GC for
//    attachments orphaned by stream errors / partial deletes.
//
//  All actual disk I/O and iCloud sync goes through `FileStorageManager`
//  — the existing infrastructure for everything else in the app — so
//  this repository stays thin. UI / `LLMPersistenceProvider` should
//  only ever talk to this repo, never to FileStorageManager directly
//  for attachment paths, since the namespace conventions and JSON
//  shape are this repo's responsibility.
//

import Foundation
import LLMCore
import Logging

// MARK: - Persisted shape

/// What gets JSON-encoded into `AIConversationMessage.filesData`.
///
/// Two kinds:
/// - `.remote` — file already lives on a content-addressable URL we
///   don't manage (typically an upload-provider URL produced by LLMKit's
///   automatic upload). We just remember the URL.
/// - `.local` — bytes we wrote to disk in the iCloud-Drive-synced
///   storage. `fileID` reconstructs the relative path; we never
///   persist absolute paths because the iCloud container path differs
///   per device.
///
/// `mimeType` is informational only — useful when we need to rebuild a
/// `data:<mime>;base64,...` URI later (e.g. for re-upload).
struct PersistedFile: Codable, Sendable, Equatable {
    enum Kind: String, Codable, Sendable {
        case remote
        case local
    }

    var kind: Kind
    /// For `.remote`: the http(s) URL string. For `.local`: nil.
    var url: String?
    /// For `.local`: the storage `fileID` we used (`<conversationID>/<UUID>`).
    /// Combined with `ext` it reconstructs the relative path under the
    /// `AIChatAttachments` namespace. For `.remote`: nil.
    var fileID: String?
    /// For `.local`: file extension (no dot). For `.remote`: nil. Pulled
    /// out of `fileID` to avoid string-splitting at every resolve.
    var ext: String?
    /// MIME type if known. Always optional, used when reconstructing
    /// data URIs for outbound provider requests.
    var mimeType: String?
}

// MARK: - Repository

actor AIChatAttachmentRepository {
    private let logger = Logger(label: "AIChatAttachmentRepository")

    private var storage: FileStorageManager { .shared }

    // MARK: - Save

    /// Translate one `ChatMessageContent.File` into a persisted record,
    /// writing bytes to disk if necessary.
    ///
    /// - Parameters:
    ///   - file: The LLMCore-side file value to persist.
    ///   - conversationID: The conversation this attachment belongs to.
    ///     Used as a namespace under `AIChatAttachments/` so the whole
    ///     subdirectory can be wiped when the conversation is deleted.
    /// - Returns: A `PersistedFile` ready to be JSON-encoded into
    ///   `AIConversationMessage.filesData`.
    func persist(
        _ file: ChatMessageContent.File,
        conversationID: String
    ) async throws -> PersistedFile {
        switch file {
            case .image(let url):
                if url.isFileURL {
                    return try await persistLocalFileURL(url, conversationID: conversationID)
                } else {
                    // http(s) — already remote, nothing to write.
                    return PersistedFile(
                        kind: .remote,
                        url: url.absoluteString,
                        fileID: nil,
                        ext: nil,
                        mimeType: nil
                    )
                }

            case .base64EncodedImage(let dataURI):
                return try await persistDataURI(dataURI, conversationID: conversationID)
        }
    }

    private func persistLocalFileURL(
        _ source: URL,
        conversationID: String
    ) async throws -> PersistedFile {
        let data = try Data(contentsOf: source)
        // Ext from source is already correct; fall back to "dat" for
        // path-less or extension-less file URLs (rare but possible for
        // temp files).
        let ext = source.pathExtension.isEmpty ? "dat" : source.pathExtension.lowercased()
        let mime = FileStorageContentType.mimeType(for: ext)
        return try await writeLocal(
            data: data,
            ext: ext,
            mimeType: mime,
            conversationID: conversationID
        )
    }

    private func persistDataURI(
        _ dataURI: String,
        conversationID: String
    ) async throws -> PersistedFile {
        guard let parsed = parseDataURI(dataURI) else {
            throw FileStorageError.writeFailed("Invalid data URI for AI chat attachment")
        }
        let ext = FileStorageContentType.fileExtension(for: parsed.mimeType)
        return try await writeLocal(
            data: parsed.data,
            ext: ext,
            mimeType: parsed.mimeType,
            conversationID: conversationID
        )
    }

    /// The single funnel for writing attachment bytes to managed
    /// storage. Centralized so the fileID format and content-type
    /// choice can't drift across the two save paths.
    private func writeLocal(
        data: Data,
        ext: String,
        mimeType: String?,
        conversationID: String
    ) async throws -> PersistedFile {
        let attachmentUUID = UUID().uuidString
        let fileID = "\(conversationID)/\(attachmentUUID)"
        _ = try await storage.saveContent(
            data,
            fileID: fileID,
            type: .aiChatAttachment(extension: ext)
        )
        return PersistedFile(
            kind: .local,
            url: nil,
            fileID: fileID,
            ext: ext,
            mimeType: mimeType
        )
    }

    // MARK: - Resolve

    /// Reverse of `persist`: rebuild an LLMCore `File` value from a
    /// stored record, pointing at whatever URL the UI should load.
    ///
    /// Returns nil only when the record is malformed (missing fields
    /// for its kind, invalid URL string, etc.). For local files that
    /// have not yet been synced down from iCloud, we still return a
    /// valid `.image(URL)` — `AsyncImage` and friends will render a
    /// placeholder until iCloud delivers the bytes.
    func resolve(_ persisted: PersistedFile) async -> ChatMessageContent.File? {
        switch persisted.kind {
            case .remote:
                guard let raw = persisted.url, let url = URL(string: raw) else {
                    logger.warning("Skipping malformed remote file record: \(String(describing: persisted))")
                    return nil
                }
                return .image(url)

            case .local:
                guard let fileID = persisted.fileID, let ext = persisted.ext else {
                    logger.warning("Skipping malformed local file record: \(String(describing: persisted))")
                    return nil
                }
                let relativePath = FileStorageContentType
                    .aiChatAttachment(extension: ext)
                    .generateRelativePath(fileID: fileID)
                do {
                    let url = try await storage.getFileURL(relativePath: relativePath)
                    return .image(url)
                } catch {
                    logger.warning("Failed to resolve local attachment URL: \(error.localizedDescription)")
                    return nil
                }
        }
    }

    // MARK: - Delete

    /// Drop every `.local` attachment for a conversation. Best-effort:
    /// individual delete failures are logged and skipped so a single
    /// dangling file can't block deleting the rest.
    ///
    /// `referencedFiles` is the union of `PersistedFile` records found
    /// across every message of the conversation — caller decodes them
    /// from `filesData` JSON. We don't query Core Data here so the
    /// repo doesn't reach across domain boundaries.
    func deleteAll(referencedFiles: [PersistedFile]) async {
        for file in referencedFiles where file.kind == .local {
            guard let fileID = file.fileID, let ext = file.ext else { continue }
            let relativePath = FileStorageContentType
                .aiChatAttachment(extension: ext)
                .generateRelativePath(fileID: fileID)
            do {
                try await storage.deleteContent(relativePath: relativePath, fileID: fileID)
            } catch {
                logger.warning("Failed to delete attachment \(relativePath): \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Garbage collection

    /// Sweep the AIChatAttachments root and delete any file not in the
    /// caller-supplied "still referenced" set. Run once on app launch
    /// (debounced) — catches leaks from crashed inserts, partial
    /// deletes, or schema drift across versions.
    ///
    /// `referencedFileIDs` is the set of `<conversationID>/<UUID>`
    /// fileIDs harvested from every message's persisted records. Files
    /// on disk are mapped back to fileIDs by stripping the directory
    /// prefix and the extension. Anything not in the set is junk.
    func garbageCollect(referencedFileIDs: Set<String>) async {
        guard let baseURL = await storage.getStorageURL() else {
            logger.warning("Skipping attachment GC: storage URL unavailable")
            return
        }
        let attachmentsRoot = baseURL.appendingPathComponent("AIChatAttachments", isDirectory: true)
        guard FileManager.default.fileExists(at: attachmentsRoot) else {
            // Directory hasn't been created yet — nothing to GC.
            return
        }

        // Two-level enumeration: <conversationID>/<UUID>.<ext>. We walk
        // each conversation subdir and consider each leaf file. Empty
        // conversation dirs (whose every file got deleted) are removed
        // too so iCloud doesn't sync ghost folders.
        guard let convoIter = try? FileManager.default.contentsOfDirectory(
            at: attachmentsRoot,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return
        }

        for conversationDir in convoIter {
            let conversationID = conversationDir.lastPathComponent
            guard let isDir = (try? conversationDir.resourceValues(forKeys: [.isDirectoryKey]).isDirectory),
                  isDir else { continue }

            let fileIter = (try? FileManager.default.contentsOfDirectory(
                at: conversationDir,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )) ?? []

            for fileURL in fileIter {
                let attachmentUUID = fileURL.deletingPathExtension().lastPathComponent
                let fileID = "\(conversationID)/\(attachmentUUID)"
                if referencedFileIDs.contains(fileID) { continue }

                do {
                    try FileManager.default.removeItem(at: fileURL)
                    logger.info("GC: removed orphan attachment \(fileID).\(fileURL.pathExtension)")
                } catch {
                    logger.warning("GC: failed to remove \(fileURL.lastPathComponent): \(error.localizedDescription)")
                }
            }

            // Drop empty conversation subdir to keep the root tidy.
            if let remaining = try? FileManager.default.contentsOfDirectory(atPath: conversationDir.filePath),
               remaining.isEmpty {
                try? FileManager.default.removeItem(at: conversationDir)
            }
        }
    }

    // MARK: - Helpers

    private func parseDataURI(_ raw: String) -> (mimeType: String, data: Data)? {
        guard raw.hasPrefix("data:") else { return nil }
        let parts = raw.dropFirst(5).split(separator: ",", maxSplits: 1)
        guard parts.count == 2 else { return nil }
        let header = String(parts[0])
        let base64 = String(parts[1])
        let mime = header.split(separator: ";").first.map(String.init) ?? "application/octet-stream"
        guard let data = Data(base64Encoded: base64) else { return nil }
        return (mime, data)
    }
}

