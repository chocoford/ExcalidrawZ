//
//  MathInputSheetModifiers.swift
//  ExcalidrawZ
//
//  Created by Codex on 2026/06/19.
//

import SwiftUI

#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

struct MathInputSheetViewModifier: ViewModifier {
    @Environment(\.alertToast) private var alertToast
    @EnvironmentObject private var fileState: FileState
    @EnvironmentObject private var canvasPreferencesState: CanvasPreferencesState
    @ObservedObject private var paywallPresentation = PaywallPresentationState.shared

    @Binding var isPresented: Bool
    @State private var restoredSnapshot: MathInputSheetSnapshot?
    @State private var shouldRestoreAfterPaywall = false
    @State private var paywallPresentationTask: Task<Void, Never>?

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $isPresented, onDismiss: handleMathInputSheetDismiss) {
                MathInputSheetView(
                    restoredSnapshot: restoredSnapshot,
                    onAIInsufficientCredits: handleAIInsufficientCredits
                ) { renderedSVG in
                    LatexMathSVGRenderer.debugPrintSVGBeforeInsert(renderedSVG.svg, source: "toolbar")
                    Task {
                        do {
                            _ = try await fileState.excalidrawWebCoordinator?.insertMathImage(
                                params: renderedSVG.mathImageParams,
                                options: .init(
                                    position: .auto,
                                    focus: .mode(.center),
                                    captureUpdate: .immediately
                                )
                            )
                        } catch {
                            alertToast(error)
                        }
                    }
                }
                .mathInputNavigationContainer()
                .swiftyAlert(logs: true)
                .task {
                    await syncMathInputCanvasAppearance(
                        from: fileState.excalidrawWebCoordinator,
                        into: canvasPreferencesState
                    )
                }
            }
            .watch(value: paywallPresentation.isPresented) { isPaywallPresented in
                guard !isPaywallPresented,
                      shouldRestoreAfterPaywall,
                      restoredSnapshot != nil else {
                    return
                }

                shouldRestoreAfterPaywall = false
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 250_000_000)
                    isPresented = true
                }
            }
            .onDisappear {
                paywallPresentationTask?.cancel()
            }
    }

    private func handleAIInsufficientCredits(_ snapshot: MathInputSheetSnapshot) {
        restoredSnapshot = snapshot
        shouldRestoreAfterPaywall = true
        copyMathInputTextToClipboard(snapshot.clipboardText)
        isPresented = false

        paywallPresentationTask?.cancel()
        paywallPresentationTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard shouldRestoreAfterPaywall else {
                return
            }
            Store.shared.togglePaywall(reason: .aiInsufficientCredits)
        }
    }

    private func handleMathInputSheetDismiss() {
        guard !shouldRestoreAfterPaywall,
              !paywallPresentation.isPresented else {
            return
        }
        restoredSnapshot = nil
    }
}

struct MathImageEditSheetViewModifier: ViewModifier {
    @EnvironmentObject private var canvasPreferencesState: CanvasPreferencesState
    @ObservedObject private var paywallPresentation = PaywallPresentationState.shared

    @ObservedObject var coordinator: ExcalidrawCore
    var onError: (Error) -> Void
    @State private var restoredSnapshot: MathInputSheetSnapshot?
    @State private var restoredEditRequest: ExcalidrawCore.MathImageEditRequest?
    @State private var shouldRestoreAfterPaywall = false
    @State private var paywallPresentationTask: Task<Void, Never>?

    private var editRequest: Binding<ExcalidrawCore.MathImageEditRequest?> {
        Binding {
            coordinator.mathImageEditRequest
        } set: { newValue in
            if newValue == nil {
                coordinator.clearMathImageEditRequest()
            }
        }
    }

    func body(content: Content) -> some View {
        content
            .sheet(item: editRequest, onDismiss: handleMathEditSheetDismiss) { request in
                MathInputSheetView(
                    mode: .edit,
                    initialLatex: request.initialLatex,
                    initialSVGColor: request.preferredSVGColor ?? "#1e1e1e",
                    restoredSnapshot: restoredSnapshot,
                    onAIInsufficientCredits: { snapshot in
                        handleAIInsufficientCredits(snapshot, editRequest: request)
                    }
                ) { renderedSVG in
                    LatexMathSVGRenderer.debugPrintSVGBeforeInsert(renderedSVG.svg, source: "edit_math")
                    Task {
                        do {
                            _ = try await coordinator.updateMathImage(
                                elementId: request.elementId,
                                params: renderedSVG.mathImageParams,
                                options: .init(
                                    focus: .enabled(false),
                                    captureUpdate: .immediately
                                )
                            )
                            coordinator.clearMathImageEditRequest()
                        } catch {
                            onError(error)
                        }
                    }
                }
                .mathInputNavigationContainer()
                .swiftyAlert(logs: true)
                .task {
                    await syncMathInputCanvasAppearance(
                        from: coordinator,
                        into: canvasPreferencesState
                    )
                }
            }
            .watch(value: paywallPresentation.isPresented) { isPaywallPresented in
                guard !isPaywallPresented,
                      shouldRestoreAfterPaywall,
                      let editRequest = restoredEditRequest else {
                    return
                }

                shouldRestoreAfterPaywall = false
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 250_000_000)
                    coordinator.requestMathImageEdit(editRequest)
                }
            }
            .onDisappear {
                paywallPresentationTask?.cancel()
            }
    }

    private func handleAIInsufficientCredits(
        _ snapshot: MathInputSheetSnapshot,
        editRequest: ExcalidrawCore.MathImageEditRequest
    ) {
        restoredSnapshot = snapshot
        restoredEditRequest = editRequest
        shouldRestoreAfterPaywall = true
        copyMathInputTextToClipboard(snapshot.clipboardText)
        coordinator.clearMathImageEditRequest()

        paywallPresentationTask?.cancel()
        paywallPresentationTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard shouldRestoreAfterPaywall else {
                return
            }
            Store.shared.togglePaywall(reason: .aiInsufficientCredits)
        }
    }

    private func handleMathEditSheetDismiss() {
        guard !shouldRestoreAfterPaywall,
              !paywallPresentation.isPresented else {
            return
        }
        restoredSnapshot = nil
        restoredEditRequest = nil
    }
}

private extension View {
    @ViewBuilder
    func mathInputNavigationContainer() -> some View {
#if os(iOS)
        NavigationStack {
            self
        }
#else
        self
#endif
    }
}

private func copyMathInputTextToClipboard(_ text: String) {
    let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedText.isEmpty else {
        return
    }

#if canImport(AppKit)
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(trimmedText, forType: .string)
#elseif canImport(UIKit)
    UIPasteboard.general.string = trimmedText
#endif
}

@MainActor
private func syncMathInputCanvasAppearance(
    from coordinator: ExcalidrawCore?,
    into canvasPreferencesState: CanvasPreferencesState
) async {
    guard let coordinator else {
        return
    }

    let preferences = try? await coordinator.fetchCanvasPreferences()
    if let preferences {
        canvasPreferencesState.apply(preferences)
    } else if let isDark = try? await coordinator.getIsDark() {
        var snapshot = CanvasPreferencesSnapshot()
        snapshot.theme = isDark ? .dark : .light
        canvasPreferencesState.apply(snapshot)
    }
}
