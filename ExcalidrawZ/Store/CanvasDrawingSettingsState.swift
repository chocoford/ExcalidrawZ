//
//  CanvasDrawingSettingsState.swift
//  ExcalidrawZ
//
//  Created by Chocoford on 5/2/26.
//

import Observation
import SwiftUI

/// Per-canvas drawing preferences (stroke color, font, roughness, etc.).
/// Lives logically under `CanvasPreferencesState`, but uses a different JS bridge
/// (`applyUserSettings` / `getUserSettings`) so it's a distinct observable model.
///
/// The web side is the source of truth — Excalidraw persists these in `appState`.
/// Inbound updates come from `apply(_:)` on file load. Outbound updates fire on
/// `didSet` of `settings`. The `isApplyingFromWeb` guard breaks the echo loop.
@MainActor
@Observable
final class CanvasDrawingSettingsState {
    /// Set by `ExcalidrawCanvasView.setupCoordinators` once the engine is ready.
    weak var coordinator: ExcalidrawCore?

    private var isApplyingFromWeb = false

    var settings: UserDrawingSettings = UserDrawingSettings() {
        didSet {
            guard !isApplyingFromWeb else { return }
            guard settings != oldValue else { return }
            let snapshot = settings
            let coordinator = self.coordinator
            Task {
                try? await coordinator?.applyUserSettings(snapshot)
            }
        }
    }

    /// Replace the current settings without echoing back to web.
    func apply(_ snapshot: UserDrawingSettings) {
        isApplyingFromWeb = true
        defer { isApplyingFromWeb = false }
        settings = snapshot
    }
}
