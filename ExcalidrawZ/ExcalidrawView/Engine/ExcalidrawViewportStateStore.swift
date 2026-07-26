//
//  ExcalidrawViewportStateStore.swift
//  ExcalidrawZ
//
//  Created by Codex on 2026/06/30.
//

import CryptoKit
import Foundation

struct ExcalidrawViewportState: Codable, Equatable, Sendable {
    var values: [String: ExcalidrawCore.JSONValue]

    var isEmpty: Bool {
        values.isEmpty
    }
}

/// Stores device-local viewport state outside the synced Excalidraw file JSON.
///
/// Excalidraw keeps `scrollX`, `scrollY`, and `zoom` in appState, but those
/// values describe the current device/window rather than collaborative file
/// content. Keeping them in a local sidecar lets opening transitions reuse the
/// last viewport without letting one device's scroll position overwrite another
/// device's file content through iCloud Drive.
actor ExcalidrawViewportStateStore {
    static let shared = ExcalidrawViewportStateStore()

    private struct StoredViewportState: Codable {
        var fileID: String
        var updatedAt: Date
        var viewport: ExcalidrawViewportState
    }

    private struct JSONValueWrapper: Codable {
        var value: ExcalidrawCore.JSONValue
    }

    private static let storedViewportKeys: Set<String> = [
        "scrollX",
        "scrollY",
        "zoom"
    ]

    private static let strippedViewportKeys: Set<String> = [
        "scrollX",
        "scrollY",
        "zoom",
        "width",
        "height"
    ]

    private init() {}

    func contentDataByApplyingStoredViewport(
        to data: Data,
        fileID: String
    ) async throws -> Data {
        guard let storedViewport = try load(fileID: fileID) else {
            if let viewport = try Self.viewport(fromContentData: data) {
                try save(viewport, fileID: fileID)
                return try Self.contentDataByApplyingViewport(
                    viewport,
                    to: data
                )
            }
            return data
        }

        return try Self.contentDataByApplyingViewport(
            storedViewport,
            to: data
        )
    }

    func contentDataBySeparatingViewport(
        from data: Data,
        fileID: String
    ) async throws -> Data {
        guard let viewport = try Self.viewport(fromContentData: data) else {
            return try Self.contentDataByRemovingViewport(from: data)
        }

        try save(viewport, fileID: fileID)
        return try Self.contentDataByRemovingViewport(from: data)
    }

    /// Preserves the source document's viewport while accepting all other
    /// appState changes from an editor running at a different offscreen size.
    func contentData(
        _ data: Data,
        preservingViewportFrom sourceData: Data
    ) throws -> Data {
        let dataWithoutViewport = try Self.contentDataByRemovingViewport(
            from: data
        )
        guard let viewport = try Self.viewport(fromContentData: sourceData) else {
            return dataWithoutViewport
        }
        return try Self.contentDataByApplyingViewport(
            viewport,
            to: dataWithoutViewport
        )
    }

    func appStateBySeparatingViewport(
        _ appState: ExcalidrawCore.JSONValue,
        fileID: String
    ) async throws -> ExcalidrawCore.JSONValue {
        let appStateObject = appState.foundationObject
        if let viewport = try Self.viewport(fromAppStateObject: appStateObject) {
            try save(viewport, fileID: fileID)
        }

        let strippedObject = Self.appStateObjectByRemovingViewport(from: appStateObject)
        return try Self.jsonValue(from: strippedObject)
    }

    private func save(_ viewport: ExcalidrawViewportState, fileID: String) throws {
        guard !viewport.isEmpty else { return }

        let stored = StoredViewportState(
            fileID: fileID,
            updatedAt: Date(),
            viewport: viewport
        )
        let data = try JSONEncoder().encode(stored)
        try data.write(to: fileURL(for: fileID), options: .atomic)
    }

    private func load(fileID: String) throws -> ExcalidrawViewportState? {
        let url = try fileURL(for: fileID)
        guard FileManager.default.fileExists(atPath: url.filePath) else {
            return nil
        }

        let data = try Data(contentsOf: url)
        let stored = try JSONDecoder().decode(StoredViewportState.self, from: data)
        return stored.viewport
    }

    private func fileURL(for fileID: String) throws -> URL {
        let directory = try storageDirectoryURL()
        let filename = Self.filename(for: fileID)
        return directory.appendingPathComponent(filename).appendingPathExtension("json")
    }

    private func storageDirectoryURL() throws -> URL {
        let appSupport = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = appSupport
            .appendingPathComponent("ViewportState", isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: nil
        )
        return directory
    }

    private static func filename(for fileID: String) -> String {
        let digest = SHA256.hash(data: Data(fileID.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private static func viewport(fromContentData data: Data) throws -> ExcalidrawViewportState? {
        guard let contentObject = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let appStateObject = contentObject["appState"] else {
            return nil
        }

        return try viewport(fromAppStateObject: appStateObject)
    }

    private static func viewport(fromAppStateObject appStateObject: Any) throws -> ExcalidrawViewportState? {
        guard let appState = appStateObject as? [String: Any] else {
            return nil
        }

        var values: [String: ExcalidrawCore.JSONValue] = [:]
        for key in storedViewportKeys {
            guard let value = appState[key],
                  !(value is NSNull) else {
                continue
            }
            values[key] = try jsonValue(from: value)
        }

        guard !values.isEmpty else { return nil }
        return ExcalidrawViewportState(values: values)
    }

    private static func contentDataByApplyingViewport(
        _ viewport: ExcalidrawViewportState,
        to data: Data
    ) throws -> Data {
        guard !viewport.isEmpty,
              var contentObject = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return data
        }

        var appStateObject = contentObject["appState"] as? [String: Any] ?? [:]
        for key in strippedViewportKeys {
            appStateObject.removeValue(forKey: key)
        }
        for (key, value) in viewport.values {
            appStateObject[key] = value.foundationObject
        }
        contentObject["appState"] = appStateObject
        return try JSONSerialization.data(withJSONObject: contentObject)
    }

    private static func contentDataByRemovingViewport(from data: Data) throws -> Data {
        guard var contentObject = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return data
        }

        guard let appStateObject = contentObject["appState"] else {
            return data
        }

        contentObject["appState"] = appStateObjectByRemovingViewport(from: appStateObject)
        return try JSONSerialization.data(withJSONObject: contentObject)
    }

    private static func appStateObjectByRemovingViewport(from appStateObject: Any) -> Any {
        guard var appState = appStateObject as? [String: Any] else {
            return appStateObject
        }

        for key in strippedViewportKeys {
            appState.removeValue(forKey: key)
        }
        return appState
    }

    private static func jsonValue(from object: Any) throws -> ExcalidrawCore.JSONValue {
        let data = try JSONSerialization.data(withJSONObject: ["value": object])
        return try JSONDecoder().decode(JSONValueWrapper.self, from: data).value
    }
}
