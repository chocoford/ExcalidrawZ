//
//  ExcalidrawCore+EditorCommandHelpers.swift
//  ExcalidrawZ
//
//  Created by Codex on 2026/06/18.
//

import Foundation

extension ExcalidrawCore {
    enum ExtraTool: String {
        case webEmbed = "webEmbed"
        case text2Diagram = "text2diagram"
        case mermaid = "mermaid"
        case magicFrame = "wireframe"
        case lasso = "lasso"
    }

    @MainActor
    func toggleToolbarAction(key: Int) async throws {
        _ = try await webView.callAsyncJavaScript(
            "window.excalidrawZHelper.toggleToolbarAction(\(key));",
            arguments: [:],
            contentWorld: .page
        )
    }

    @MainActor
    func activateHandTool() async throws {
        guard !self.isLoading else { return }
        let previousLastTool = self.lastTool
        self.lastTool = .hand
        do {
            _ = try await webView.callAsyncJavaScript(
                """
                const helper = window.excalidrawZHelper;
                if (!helper || typeof helper.toggleToolbarAction !== "function") {
                    throw new Error("Excalidraw helper is not ready.");
                }
                const api = helper._api;
                if (api && typeof api.setActiveTool === "function") {
                    try {
                        api.setActiveTool({ type: "hand" });
                    } catch (_) {
                        helper.toggleToolbarAction("H");
                    }
                } else {
                    helper.toggleToolbarAction("H");
                }
                """,
                arguments: [:],
                contentWorld: .page
            )
        } catch {
            self.lastTool = previousLastTool
            throw error
        }
    }

    @MainActor
    func clearPreviousSelection() async throws {
        guard !self.isLoading else { return }
        _ = try await webView.callAsyncJavaScript(
            "window.excalidrawZHelper.clearPreviousSelection();",
            arguments: [:],
            contentWorld: .page
        )
    }

    @MainActor
    func toggleToolbarAction(key: Character) async throws {
        guard !self.isLoading else { return }
        let toolbarKey: String
        if key == "\u{1B}" {
            toolbarKey = "Escape"
        } else if key == " " {
            toolbarKey = "Space"
        } else {
            toolbarKey = key.uppercased()
        }
        _ = try await webView.callAsyncJavaScript(
            "window.excalidrawZHelper.toggleToolbarAction('\(toolbarKey)');",
            arguments: [:],
            contentWorld: .page
        )
    }

    @MainActor
    func toggleDeleteAction() async throws {
        guard !self.isLoading else { return }
        _ = try await webView.callAsyncJavaScript(
            "window.excalidrawZHelper.toggleToolbarAction('Backspace');",
            arguments: [:],
            contentWorld: .page
        )
    }

    @MainActor
    func toggleToolbarAction(tool: ExtraTool) async throws {
        guard !self.isLoading else { return }
        _ = try await webView.callAsyncJavaScript(
            "window.excalidrawZHelper.toggleToolbarAction('\(tool.rawValue)');",
            arguments: [:],
            contentWorld: .page
        )
    }

    @MainActor
    func performUndo() async throws {
        _ = try await webView.callAsyncJavaScript(
            "window.excalidrawZHelper.undo();",
            arguments: [:],
            contentWorld: .page
        )
    }

    @MainActor
    func performRedo() async throws {
        _ = try await webView.callAsyncJavaScript(
            "window.excalidrawZHelper.redo();",
            arguments: [:],
            contentWorld: .page
        )
    }

    @MainActor
    func connectPencil(enabled: Bool) async throws {
        _ = try await webView.callAsyncJavaScript(
            "window.excalidrawZHelper.connectPencil(\(enabled));",
            arguments: [:],
            contentWorld: .page
        )
    }

    @MainActor
    func togglePenMode(enabled: Bool) async throws {
        _ = try await webView.callAsyncJavaScript(
            "window.excalidrawZHelper.togglePenMode(\(enabled));",
            arguments: [:],
            contentWorld: .page
        )
    }

    @MainActor
    public func toggleActionsMenu(isPresented: Bool) async throws {
        _ = try await webView.callAsyncJavaScript(
            "window.excalidrawZHelper.toggleActionsMenu(\(isPresented));",
            arguments: [:],
            contentWorld: .page
        )
    }

    @MainActor
    public func setPointerInputPolicy(mode: ToolState.PencilInteractionMode) async throws {
        _ = try await webView.callAsyncJavaScript(
            """
            window.excalidrawZHelper.setPointerInputPolicy({
              oneFingerAction: "\(mode.oneFingerAction)",
              penPriority: \(mode.penPriority),
            });
            """,
            arguments: [:],
            contentWorld: .page
        )
    }
}
