//
//  ExcalidrawCore+FileSessionHelpers.swift
//  ExcalidrawZ
//
//  Created by Codex on 2026/06/18.
//

import Foundation

extension ExcalidrawCore {
    /// Save `currentFile` or creating if neccessary.
    ///
    /// This function will get the local storage of `excalidraw.com`.
    /// Then it will set the data got from local storage to `currentFile`.
    /// Returns `{ dataString, elementCount }` from the JS side.
    @MainActor
    @discardableResult
    func saveCurrentFile() async throws -> SaveFileResult? {
        let raw = try await self.webView.callAsyncJavaScript(
            "return await window.excalidrawZHelper.saveFile();",
            arguments: [:],
            contentWorld: .page
        )
        return SaveFileResult(fromJS: raw)
    }

    /// Returns a one-time snapshot copy of the current live canvas without
    /// participating in the persistence/autosave flow. Use this for AI tools
    /// and debug reads that need editor state newer than the throttled
    /// `onStateChanged` broadcast. Callers that only need live elements can
    /// omit files to avoid streaming large media payloads across the bridge.
    @MainActor
    func getCurrentFileSnapshot(
        preferSaveStream: Bool = true,
        includeFiles: Bool = true
    ) async throws -> CurrentFileSnapshot {
        guard !self.webView.isLoading else {
            throw InvalidJavaScriptResult()
        }
        if preferSaveStream {
            do {
                return try await getCurrentFileSnapshotUsingSaveStream(
                    includeFiles: includeFiles
                )
            } catch CurrentFileSaveStreamError.unsupported {
                logger.debug("Current file save stream is not supported; falling back to direct snapshot.")
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                logger.warning("Current file save stream failed; falling back to direct snapshot: \(error)")
            }
        }

        let result = try await self.webView.callAsyncJavaScript(
            "return await window.excalidrawZHelper.getCurrentFileSnapshot();",
            arguments: [:],
            contentWorld: .page
        )
        let snapshot = try CurrentFileSnapshot.fromJavaScriptResult(result)
        guard !includeFiles else {
            return snapshot
        }
        return CurrentFileSnapshot(
            revision: snapshot.revision,
            elementCount: snapshot.elementCount,
            fileCount: 0,
            documentData: try snapshot.documentData(includeFiles: false)
        )
    }

    @MainActor
    func getCurrentAppState() async throws -> JSONValue {
        guard !self.webView.isLoading else {
            throw InvalidJavaScriptResult()
        }
        let result = try await self.webView.callAsyncJavaScript(
            """
            const api = window.excalidrawZHelper?._api;
            if (!api || typeof api.getAppState !== "function") {
                throw new Error("Excalidraw API is not ready.");
            }
            return JSON.stringify(api.getAppState());
            """,
            arguments: [:],
            contentWorld: .page
        )
        guard let jsonString = result as? String,
              let data = jsonString.data(using: .utf8) else {
            throw InvalidJavaScriptResult()
        }
        return try JSONDecoder().decode(JSONValue.self, from: data)
    }

    @MainActor
    private func getCurrentFileSnapshotUsingSaveStream(
        includeFiles: Bool
    ) async throws -> CurrentFileSnapshot {
        let result = try await requestCurrentFileSaveStream(
            includeFiles: includeFiles
        )
        return CurrentFileSnapshot(saveStreamResult: result)
    }

    /// Low-level stream request wrapper. The stream protocol itself lives in
    /// `CurrentFileSaveStreamBridge`; callers should normally use
    /// `getCurrentFileSnapshot()`, which streams by default and falls back to a
    /// direct bridge read when needed.
    @MainActor
    func requestCurrentFileSaveStream(
        includeFiles: Bool,
        chunkSize: Int = 65_536,
        timeoutNanoseconds: UInt64 = 30_000_000_000
    ) async throws -> CurrentFileSaveStreamResult {
        guard !self.webView.isLoading else {
            throw InvalidJavaScriptResult()
        }

        return try await currentFileSaveStreamBridge.request(
            webView: webView,
            includeFiles: includeFiles,
            chunkSize: chunkSize,
            timeoutNanoseconds: timeoutNanoseconds
        )
    }

    /// `true` if is dark mode.
    @MainActor
    func getIsDark() async throws -> Bool {
        if self.webView.isLoading { return false }
        let res = try await self.webView.callAsyncJavaScript(
            "return window.excalidrawZHelper.getIsDark();",
            arguments: [:],
            contentWorld: .page
        )
        if let isDark = res as? Bool {
            return isDark
        } else {
            return false
        }
    }

    @MainActor
    func changeColorMode(dark: Bool) async throws {
        if self.webView.isLoading { return }
        let isDark = try await getIsDark()
        guard isDark != dark else { return }
        _ = try await webView.callAsyncJavaScript(
            "window.excalidrawZHelper.toggleColorTheme(\"\(dark ? "dark" : "light")\");",
            arguments: [:],
            contentWorld: .page
        )
    }

    @MainActor
    @discardableResult
    func loadLibraryItem(item: ExcalidrawLibrary) async throws -> LoadLibraryItemResult? {
        let libraryItemsJSON = try item.libraryItems.jsonStringified()
        let raw = try await self.webView.callAsyncJavaScript(
            "return await window.excalidrawZHelper.loadLibraryItem(\(libraryItemsJSON));",
            arguments: [:],
            contentWorld: .page
        )
        return LoadLibraryItemResult(fromJS: raw)
    }
}
