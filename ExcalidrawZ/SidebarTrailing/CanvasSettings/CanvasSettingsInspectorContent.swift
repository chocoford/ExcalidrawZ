//
//  CanvasSettingsInspectorContent.swift
//  ExcalidrawZ
//
//  Created by Chocoford on 5/2/26.
//

import SwiftUI

import ChocofordUI

/// Inspector content for canvas-level preferences. Bindings drive `CanvasPreferencesState`
/// directly — its per-field `didSet` pushes partial updates to the web side.
struct CanvasSettingsInspectorContent: View {
    @EnvironmentObject var fileState: FileState
    @EnvironmentObject var layoutState: LayoutState
    @EnvironmentObject var appPreference: AppPreference
    @EnvironmentObject var canvasPrefs: CanvasPreferencesState

    /// Tool lock isn't part of canvas preferences — it's still driven by `toggleToolbarAction("Q")`.
    @State private var toolLockEnabled: Bool = false

    /// UI-only override for the drawing-prefs section. When false, the "is customized"
    /// state is purely derived from the canvas-vs-global comparison. User toggling the
    /// switch ON sets this to true (sticky until reset / file switch).
    @State private var customizeDrawingSettingsOverride: Bool = false

    var body: some View {
#if os(macOS)
        if appPreference.inspectorLayout == .sidebar {
            content()
                .toolbar {
                    InspectorHeaderToolbar(
                        title: String(localizable: .canvasPreferencesTitle),
                        isInspectorPresented: layoutState.isInspectorPresented
                    )
                }
        } else {
            content()
        }
#else
        content()
#endif
    }

    @ViewBuilder
    private func content() -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                canvasBackgroundRow

                Divider()

                selectModeRow

                Divider()

                shortcutToggles

                Divider()

                plainToggles

                Divider()

                drawingPreferencesSection
            }
            .padding(16)
        }
        .onChange(of: fileState.currentActiveFile) { _ in
            // New file → drop the manual override so the toggle reflects the new
            // canvas's actual relationship to the global defaults.
            customizeDrawingSettingsOverride = false
        }
    }

    @ViewBuilder
    private var canvasBackgroundRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(localizable: .canvasPreferencesCanvasBackgroundTitle)
            ColorButtonGroup(
                colors: ColorPalette.canvasBackgroundQuickPicks,
                selectedColor: canvasPrefs.viewBackgroundColor
            ) { color in
                canvasPrefs.viewBackgroundColor = color
            }
        }
    }

    @ViewBuilder
    private var selectModeRow: some View {
        HStack {
            Text(localizable: .canvasPreferencesSelectOnTitle)
            Spacer()
            Picker(
                String(localizable: .canvasPreferencesSelectOnTitle),
                selection: $canvasPrefs.boxSelectionMode
            ) {
                Text(
                    localizable: .canvasPreferencesSelectOnOptionWrap
                ).tag(CanvasPreferencesState.BoxSelectionMode.contain)
                Text(
                    localizable: .canvasPreferencesSelectOnOptionOverlap
                ).tag(CanvasPreferencesState.BoxSelectionMode.overlap)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .modernButtonStyle(style: .glass, size: .regular, shape: .capsule)
        }
    }

    @ViewBuilder
    private var shortcutToggles: some View {
        VStack(alignment: .leading, spacing: 8) {
            toggleRow(
                String(localizable: .canvasPreferencesToolLockTitle),
                shortcut: "Q",
                isOn: toolLockBinding
            )
            toggleRow(
                String(localizable: .canvasPreferencesSnapToMidpointsTitle),
                shortcut: "⌥S",
                isOn: $canvasPrefs.objectsSnapModeEnabled
            )
            toggleRow(
                String(localizable: .canvasPreferencesToggleGridTitle),
                shortcut: "⌘'",
                isOn: $canvasPrefs.gridModeEnabled
            )
            toggleRow(
                String(localizable: .canvasPreferencesZenModeTitle),
                shortcut: "⌥Z",
                isOn: $canvasPrefs.zenModeEnabled
            )
            toggleRow(
                String(localizable: .canvasPreferencesViewModeTitle),
                shortcut: "⌥R",
                isOn: $canvasPrefs.viewModeEnabled
            )
            toggleRow(
                String(localizable: .canvasPreferencesStatesTitle),
                shortcut: "⌥/",
                isOn: $canvasPrefs.stats
            )
        }
    }

    @ViewBuilder
    private var plainToggles: some View {
        VStack(alignment: .leading, spacing: 8) {
            toggleRow(
                String(localizable: .canvasPreferencesArrowBindingTitle),
                shortcut: nil,
                isOn: bindingPreferenceBinding
            )
            toggleRow(
                String(localizable: .canvasPreferencesSnapToMidpointsTitle),
                shortcut: nil,
                isOn: $canvasPrefs.isMidpointSnappingEnabled
            )
        }
    }

    // MARK: - Drawing Preferences

    @ViewBuilder
    private var drawingPreferencesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Drawing Preferences")
                    .font(.headline)

                Spacer()

                Toggle(isOn: customizeDrawingSettingsBinding) {}
                .toggleStyle(.switch)
                .controlSize(.mini)
            }
            Text(isCustomizingDrawingSettings
                 ? "This canvas overrides the global defaults. Turn off to reset."
                 : "Following the global defaults from Settings → Excalidraw.")
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)

            DrawingSettingsPanel(
                settings: drawingSettingsBinding,
                onSettingsChange: {}
            )
            .disabled(!isCustomizingDrawingSettings)
            .opacity(isCustomizingDrawingSettings ? 1 : 0.55)
            .padding(.top, 4)
        }
    }

    /// True when the toggle should appear ON. Either the user explicitly turned it on,
    /// or the canvas's settings disagree with the global template.
    private var isCustomizingDrawingSettings: Bool {
        customizeDrawingSettingsOverride || !isFollowingGlobalDrawingSettings
    }

    /// Flipping OFF resets the canvas to the global template; flipping ON only unlocks
    /// the panel — values stay where they were until the user actually edits.
    private var customizeDrawingSettingsBinding: Binding<Bool> {
        Binding(
            get: { isCustomizingDrawingSettings },
            set: { newValue in
                if newValue {
                    customizeDrawingSettingsOverride = true
                } else {
                    resetDrawingSettingsToGlobal()
                }
            }
        )
    }

    /// Comparison happens after both sides are filled with UI defaults — same lens the
    /// Settings panel applies — so a stored nil and the rendered default count as equal.
    private var isFollowingGlobalDrawingSettings: Bool {
        canvasPrefs.drawingSettings.settings.matches(
            template: appPreference.customDrawingSettings
        )
    }

    private var drawingSettingsBinding: Binding<UserDrawingSettings> {
        Binding(
            get: { canvasPrefs.drawingSettings.settings },
            set: { canvasPrefs.drawingSettings.settings = $0 }
        )
    }

    /// Make the canvas look identical to the global view — fields global has set win,
    /// the rest fall back to the same UI defaults the Settings panel renders. Without
    /// the `filling(defaults:)` step, canvas-only divergence (e.g. a fontSize the user
    /// picked via Excalidraw) would survive reset and leave the inspector saying
    /// "customized" even after the user asked to follow global.
    private func resetDrawingSettingsToGlobal() {
        canvasPrefs.drawingSettings.settings = appPreference.customDrawingSettings
            .filling(defaults: .uiDefaults)
        customizeDrawingSettingsOverride = false
    }

    @ViewBuilder
    private func toggleRow(_ title: String, shortcut: String?, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            HStack {
                Text(title)
                Spacer()
                if let shortcut {
                    if #available(macOS 13.0, *) {
                        Text(shortcut)
                            .foregroundStyle(.secondary)
                            .monospaced()
                    } else {
                        Text(shortcut)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .toggleStyle(.switch)
    }

    // MARK: - UI-only Bindings

    /// Arrow binding: enum on the wire, Bool in the UI.
    private var bindingPreferenceBinding: Binding<Bool> {
        Binding(
            get: { canvasPrefs.bindingPreference == .enabled },
            set: { canvasPrefs.bindingPreference = $0 ? .enabled : .disabled }
        )
    }

    /// Tool lock: not in canvas preferences — uses the toolbar action shortcut "Q".
    private var toolLockBinding: Binding<Bool> {
        Binding(
            get: { toolLockEnabled },
            set: { newValue in
                toolLockEnabled = newValue
                Task {
                    try? await fileState.excalidrawWebCoordinator?.toggleToolbarAction(key: Character("q"))
                }
            }
        )
    }

}
