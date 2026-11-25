//
//  CanvasPreferencesState.swift
//  ExcalidrawZ
//
//  Created by Chocoford on 5/2/26.
//

import Observation
import SwiftUI

/// Mirror of the canvas-level preferences exposed by `excalidrawZHelper`.
///
/// Web is the source of truth. Inbound updates arrive via `apply(_:)` (called from the
/// `onCanvasPreferencesChanged` handler). Outbound updates fire automatically on `didSet` —
/// any change to a field pushes a partial update to `coordinator.setCanvasPreferences`.
///
/// The `isApplyingFromWeb` guard breaks the web → apply → didSet → web echo loop. It works
/// because `apply()` is synchronous on main, so each `didSet` runs while the flag is still set.
@MainActor
@Observable
final class CanvasPreferencesState {
    enum Theme: String, Codable, Hashable, Sendable {
        case light
        case dark
    }

    enum BindingPreference: String, Codable, Hashable, Sendable {
        case enabled
        case disabled
    }

    enum PreferredSelectionTool: String, Codable, Hashable, Sendable {
        case selection
        case lasso
    }

    /// Wrap (contain): elements must be fully inside the box.
    /// Overlap: any intersection counts.
    enum BoxSelectionMode: String, Codable, Hashable, Sendable {
        case contain
        case overlap
    }

    /// Set by `ExcalidrawCanvasView.setupCoordinators` once the engine is ready.
    weak var coordinator: ExcalidrawCore? {
        didSet { drawingSettings.coordinator = coordinator }
    }

    /// Drawing-level prefs (stroke color, font, roughness, etc.). Conceptually a
    /// child of canvas preferences, with its own observable fields and JS bridge.
    let drawingSettings = CanvasDrawingSettingsState()

    private var isApplyingFromWeb = false

    var theme: Theme = .light {
        didSet { pushField { $0.theme = theme } }
    }
    var viewBackgroundColor: String = "#ffffff" {
        didSet { pushField { $0.viewBackgroundColor = viewBackgroundColor } }
    }
    var gridModeEnabled: Bool = false {
        didSet { pushField { $0.gridModeEnabled = gridModeEnabled } }
    }
    var zenModeEnabled: Bool = false {
        didSet { pushField { $0.zenModeEnabled = zenModeEnabled } }
    }
    var viewModeEnabled: Bool = false {
        didSet { pushField { $0.viewModeEnabled = viewModeEnabled } }
    }
    var objectsSnapModeEnabled: Bool = false {
        didSet { pushField { $0.objectsSnapModeEnabled = objectsSnapModeEnabled } }
    }
    var isMidpointSnappingEnabled: Bool = true {
        didSet { pushField { $0.isMidpointSnappingEnabled = isMidpointSnappingEnabled } }
    }
    var bindingPreference: BindingPreference = .enabled {
        didSet { pushField { $0.bindingPreference = bindingPreference } }
    }
    var preferredSelectionTool: PreferredSelectionTool = .selection {
        didSet { pushField { $0.preferredSelectionTool = preferredSelectionTool } }
    }
    var boxSelectionMode: BoxSelectionMode = .contain {
        didSet { pushField { $0.boxSelectionMode = boxSelectionMode } }
    }
    var stats: Bool = false {
        didSet { pushField { $0.stats = stats } }
    }

    /// Apply a partial diff (from `onCanvasPreferencesChanged`) or a full snapshot.
    /// Suppresses the per-field didSet push for the duration.
    func apply(_ snapshot: CanvasPreferencesSnapshot) {
        isApplyingFromWeb = true
        defer { isApplyingFromWeb = false }
        if let value = snapshot.theme { theme = value }
        if let value = snapshot.viewBackgroundColor { viewBackgroundColor = value }
        if let value = snapshot.gridModeEnabled { gridModeEnabled = value }
        if let value = snapshot.zenModeEnabled { zenModeEnabled = value }
        if let value = snapshot.viewModeEnabled { viewModeEnabled = value }
        if let value = snapshot.objectsSnapModeEnabled { objectsSnapModeEnabled = value }
        if let value = snapshot.isMidpointSnappingEnabled { isMidpointSnappingEnabled = value }
        if let value = snapshot.bindingPreference { bindingPreference = value }
        if let value = snapshot.preferredSelectionTool { preferredSelectionTool = value }
        if let value = snapshot.boxSelectionMode { boxSelectionMode = value }
        if let value = snapshot.stats { stats = value }
    }

    private func pushField(_ build: (inout CanvasPreferencesSnapshot) -> Void) {
        guard !isApplyingFromWeb else { return }
        var update = CanvasPreferencesSnapshot()
        build(&update)
        let coordinator = self.coordinator
        Task {
            try? await coordinator?.setCanvasPreferences(update)
        }
    }
}

/// All-optional payload shared by the inbound diff event and the outbound partial-update call.
/// Only non-nil fields are encoded — matching the partial-update contract on the JS side.
struct CanvasPreferencesSnapshot: Codable, Sendable {
    var theme: CanvasPreferencesState.Theme?
    var viewBackgroundColor: String?
    var gridModeEnabled: Bool?
    var zenModeEnabled: Bool?
    var viewModeEnabled: Bool?
    var objectsSnapModeEnabled: Bool?
    var isMidpointSnappingEnabled: Bool?
    var bindingPreference: CanvasPreferencesState.BindingPreference?
    var preferredSelectionTool: CanvasPreferencesState.PreferredSelectionTool?
    var boxSelectionMode: CanvasPreferencesState.BoxSelectionMode?
    var stats: Bool?

    enum CodingKeys: String, CodingKey {
        case theme
        case viewBackgroundColor
        case gridModeEnabled
        case zenModeEnabled
        case viewModeEnabled
        case objectsSnapModeEnabled
        case isMidpointSnappingEnabled
        case bindingPreference
        case preferredSelectionTool
        case boxSelectionMode
        case stats
    }

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        theme = Self.decodeStringEnum(
            CanvasPreferencesState.Theme.self,
            from: container,
            forKey: .theme
        )
        viewBackgroundColor = try? container.decodeIfPresent(
            String.self,
            forKey: .viewBackgroundColor
        )
        gridModeEnabled = Self.decodeBool(from: container, forKey: .gridModeEnabled)
        zenModeEnabled = Self.decodeBool(from: container, forKey: .zenModeEnabled)
        viewModeEnabled = Self.decodeBool(from: container, forKey: .viewModeEnabled)
        objectsSnapModeEnabled = Self.decodeBool(
            from: container,
            forKey: .objectsSnapModeEnabled
        )
        isMidpointSnappingEnabled = Self.decodeBool(
            from: container,
            forKey: .isMidpointSnappingEnabled
        )
        bindingPreference = Self.decodeBindingPreference(
            from: container,
            forKey: .bindingPreference
        )
        preferredSelectionTool = Self.decodeStringEnum(
            CanvasPreferencesState.PreferredSelectionTool.self,
            from: container,
            forKey: .preferredSelectionTool
        )
        boxSelectionMode = Self.decodeStringEnum(
            CanvasPreferencesState.BoxSelectionMode.self,
            from: container,
            forKey: .boxSelectionMode
        )
        stats = Self.decodeBool(from: container, forKey: .stats)
    }

    var isEmpty: Bool {
        theme == nil &&
        viewBackgroundColor == nil &&
        gridModeEnabled == nil &&
        zenModeEnabled == nil &&
        viewModeEnabled == nil &&
        objectsSnapModeEnabled == nil &&
        isMidpointSnappingEnabled == nil &&
        bindingPreference == nil &&
        preferredSelectionTool == nil &&
        boxSelectionMode == nil &&
        stats == nil
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(theme, forKey: .theme)
        try container.encodeIfPresent(viewBackgroundColor, forKey: .viewBackgroundColor)
        try container.encodeIfPresent(gridModeEnabled, forKey: .gridModeEnabled)
        try container.encodeIfPresent(zenModeEnabled, forKey: .zenModeEnabled)
        try container.encodeIfPresent(viewModeEnabled, forKey: .viewModeEnabled)
        try container.encodeIfPresent(objectsSnapModeEnabled, forKey: .objectsSnapModeEnabled)
        try container.encodeIfPresent(isMidpointSnappingEnabled, forKey: .isMidpointSnappingEnabled)
        try container.encodeIfPresent(bindingPreference, forKey: .bindingPreference)
        try container.encodeIfPresent(preferredSelectionTool, forKey: .preferredSelectionTool)
        try container.encodeIfPresent(boxSelectionMode, forKey: .boxSelectionMode)
        try container.encodeIfPresent(stats, forKey: .stats)
    }

    private static func decodeStringEnum<T: RawRepresentable>(
        _ type: T.Type,
        from container: KeyedDecodingContainer<CodingKeys>,
        forKey key: CodingKeys
    ) -> T? where T.RawValue == String {
        guard let rawValue = try? container.decodeIfPresent(String.self, forKey: key) else {
            return nil
        }
        return T(rawValue: rawValue)
    }

    private static func decodeBindingPreference(
        from container: KeyedDecodingContainer<CodingKeys>,
        forKey key: CodingKeys
    ) -> CanvasPreferencesState.BindingPreference? {
        if let value = decodeStringEnum(
            CanvasPreferencesState.BindingPreference.self,
            from: container,
            forKey: key
        ) {
            return value
        }
        if let boolValue = decodeBool(from: container, forKey: key) {
            return boolValue ? .enabled : .disabled
        }
        return nil
    }

    private static func decodeBool(
        from container: KeyedDecodingContainer<CodingKeys>,
        forKey key: CodingKeys
    ) -> Bool? {
        if let value = try? container.decodeIfPresent(Bool.self, forKey: key) {
            return value
        }
        if let value = try? container.decodeIfPresent(Int.self, forKey: key) {
            return value != 0
        }
        if let value = try? container.decodeIfPresent(Double.self, forKey: key) {
            return value != 0
        }
        guard let rawValue = try? container.decodeIfPresent(String.self, forKey: key) else {
            return nil
        }
        switch rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            case "true", "yes", "1", "enabled", "on":
                return true
            case "false", "no", "0", "disabled", "off":
                return false
            default:
                return nil
        }
    }
}
