//
//  ExcalidrawDocumentAppStatePersistence.swift
//  ExcalidrawZ
//
//  Created by Codex on 2026/6/30.
//

import Foundation

enum ExcalidrawDocumentAppStatePersistence {
    private static let appStateOnlyPersistentKeys: Set<String> = [
        // Canvas preferences
        // `theme` is intentionally excluded: native appearance settings apply it at runtime.
        "viewBackgroundColor",
        "gridSize",
        "gridStep",
        "gridModeEnabled",
        "zenModeEnabled",
        "viewModeEnabled",
        "objectsSnapModeEnabled",
        "isMidpointSnappingEnabled",
        "bindingPreference",
        "preferredSelectionTool",
        "boxSelectionMode",
        "stats",

        // Drawing defaults
        "currentItemStrokeWidthKey",
        "currentItemStrokeColor",
        "currentItemBackgroundColor",
        "currentItemStrokeStyle",
        "currentItemFillStyle",
        "currentItemRoughness",
        "currentItemOpacity",
        "currentItemFontFamily",
        "currentItemFontSize",
        "currentItemTextAlign",
        "currentItemRoundness",
        "currentItemArrowType",
        "currentItemStartArrowhead",
        "currentItemEndArrowhead",
        "currentItemStrokeVariability"
    ]

    static func documentData(
        _ documentData: Data,
        settingNativeFileName nativeFileName: String?
    ) throws -> Data {
        guard var documentObject = try JSONSerialization.jsonObject(with: documentData) as? [String: Any] else {
            return documentData
        }

        var appState = documentObject["appState"] as? [String: Any] ?? [:]
        // Collaboration presence is runtime-only. Upstream Excalidraw strips
        // it from file exports; retaining a bridged Map as `{}` breaks clients
        // that expect restored collaborators to be a Map/array-like value.
        appState.removeValue(forKey: "collaborators")
        if let nativeFileName, !nativeFileName.isEmpty {
            appState["name"] = nativeFileName
        }
        documentObject["appState"] = appState

        return try JSONSerialization.data(withJSONObject: documentObject)
    }

    static func appStateObjectByKeepingAppStateOnlyPersistentFields(from appStateObject: Any) -> [String: Any] {
        guard let appState = appStateObject as? [String: Any] else {
            return [String: Any]()
        }

        return appState.filter { appStateOnlyPersistentKeys.contains($0.key) }
    }

    static func appStateObjectByMergingAppStateOnlyPersistentFields(
        from appStateObject: Any,
        into existingAppStateObject: Any,
        nativeFileName: String?
    ) -> Any {
        var mergedAppState = existingAppStateObject as? [String: Any] ?? [:]
        let appState = appStateObject as? [String: Any] ?? [:]

        for key in appStateOnlyPersistentKeys {
            if let value = appState[key] {
                mergedAppState[key] = value
            } else {
                mergedAppState.removeValue(forKey: key)
            }
        }

        if let nativeFileName, !nativeFileName.isEmpty {
            mergedAppState["name"] = nativeFileName
        }

        return mergedAppState
    }

}
