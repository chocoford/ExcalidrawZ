//
//  DebugPanelView.swift
//  ExcalidrawZ
//
//  Created by Codex
//

#if DEBUG
import SwiftUI
import LLMCore

struct DebugPanelView: View {
    @EnvironmentObject private var fileState: FileState

    private let actionColumns = [
        GridItem(.flexible(minimum: 100), spacing: 8),
        GridItem(.flexible(minimum: 100), spacing: 8)
    ]

    @State private var cameraScrollXText = "0"
    @State private var cameraScrollYText = "0"
    @State private var cameraZoomText = "1"
    @State private var cameraElementID = ""
    @State private var fitElementIDsText = ""
    @State private var scrollMode: ExcalidrawCore.ScrollToElementMode = .fitContent
    @State private var scrollViewportZoomFactorText = "0.7"
    @State private var scrollMinZoomText = ""
    @State private var scrollMaxZoomText = ""
    @State private var adjustPayload = """
    {
      "dryRun": false,
      "ops": [
        {
          "op": "add",
          "element": {
            "type": "text",
            "text": "Hello from Debug"
          }
        }
      ]
    }
    """

    @State private var isDryRun = false
    @State private var isRunning = false
    @State private var lastResult = ""
    @State private var lastError = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                debugHeader
                cameraSection
                adjustSection
                logsSection
            }
            .padding(12)
        }
        .scrollIndicators(.hidden)
    }

    private var cameraTarget: ExcalidrawCoordinatorRegistry.CanvasTarget {
        switch fileState.currentActiveFile {
            case .collaborationFile:
                .collaboration
            default:
                .normal
        }
    }

    private var activeCoordinator: ExcalidrawCanvasView.Coordinator? {
        switch cameraTarget {
            case .normal:
                fileState.excalidrawWebCoordinator
            case .collaboration:
                fileState.excalidrawCollaborationWebCoordinator
        }
    }

    private var cameraDirector: AICameraDirector {
        ExcalidrawCoordinatorRegistry.shared.cameraDirector(for: cameraTarget)
    }

    private var selectedElementIDs: [String] {
        activeCoordinator?.selectedElementIDs ?? []
    }

    private var selectionSummary: String {
        guard let firstID = selectedElementIDs.first else {
            return "Selection: none"
        }
        if selectedElementIDs.count == 1 {
            return "Selection: \(firstID)"
        }
        return "Selection: \(firstID) +\(selectedElementIDs.count - 1)"
    }

    @ViewBuilder
    private var cameraSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                statusBadge(selectionSummary, systemImage: "cursorarrow.click.2")
                statusBadge("Director: \(cameraDirector.debugSnapshot().phase)", systemImage: "movieclapper")

                LazyVGrid(columns: actionColumns, spacing: 8) {
                    debugActionButton("Get Camera") {
                        runCameraAction("Get Camera") {
                            let camera = try await requireCoordinator().getCamera()
                            await MainActor.run {
                                cameraScrollXText = camera.scrollX.formatted()
                                cameraScrollYText = camera.scrollY.formatted()
                                cameraZoomText = camera.zoom.formatted()
                            }
                            return "camera=\(camera)"
                        }
                    }

                    debugActionButton("Scroll To Center") {
                        runCameraAction("Scroll To Center") {
                            try await requireCoordinator().scrollToCenter()
                            return "Centered canvas."
                        }
                    }

                    debugActionButton("Focus Selection") {
                        runCameraAction("Focus Selection") {
                            let ids = try requireSelectionIDs()
                            try await requireCoordinator().zoomToFitElements(ids: ids)
                            return "Focused selection: \(ids.joined(separator: ", "))."
                        }
                    }

                    debugActionButton("Zoom To Fit All") {
                        runCameraAction("Zoom To Fit All") {
                            try await requireCoordinator().zoomToFit()
                            return "Zoomed to fit content."
                        }
                    }

                    debugActionButton("Director Snapshot") {
                        lastResult = "[Camera Director]\n\(cameraDirector.debugSnapshot().description)"
                    }

                    debugActionButton("Stop Director") {
                        cameraDirector.stop()
                        lastResult = "[Camera Director]\nStopped director."
                    }
                }

                debugCard("AI Camera Director", systemImage: "video") {
                    Text("Test path: begin a session, submit one or more focus updates, then end the session and observe Excalidraw-side follow and settle. Use the staged demo to simulate bursty AI updates.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: 8) {
                        debugActionButton("Begin Session") {
                            isRunning = true
                            lastError = ""
                            Task {
                                do {
                                    await MainActor.run {
                                        syncCoordinatorRegistry()
                                    }
                                    try await cameraDirector.beginSession()
                                    await MainActor.run {
                                        lastResult = "[Camera Director]\nBegan session."
                                        isRunning = false
                                    }
                                } catch {
                                    await MainActor.run {
                                        lastError = "[Camera Director]\n\(error.localizedDescription)"
                                        isRunning = false
                                    }
                                }
                            }
                        }

                        debugActionButton("End Session") {
                            isRunning = true
                            lastError = ""
                            Task {
                                do {
                                    await MainActor.run {
                                        syncCoordinatorRegistry()
                                    }
                                    try await cameraDirector.endSession()
                                    await MainActor.run {
                                        lastResult = "[Camera Director]\nEnded session with settle."
                                        isRunning = false
                                    }
                                } catch {
                                    await MainActor.run {
                                        lastError = "[Camera Director]\n\(error.localizedDescription)"
                                        isRunning = false
                                    }
                                }
                            }
                        }
                    }

                    HStack(spacing: 8) {
                        debugActionButton("Track Selection") {
                            runTrackSelection()
                        }

                        debugActionButton("Run Staged Demo") {
                            runStagedDirectorDemo()
                        }
                    }

                    debugActionButton("Inspect Follow") {
                        runInspectFollow()
                    }
                }

                debugCard("Set Camera", systemImage: "move.3d") {
                    HStack(spacing: 8) {
                        compactField("scrollX", text: $cameraScrollXText)
                        compactField("scrollY", text: $cameraScrollYText)
                        compactField("zoom", text: $cameraZoomText)
                    }

                    debugActionButton("Apply Camera Patch") {
                        runCameraAction("Set Camera") {
                            let patch = ExcalidrawCore.CameraPatch(
                                scrollX: Double(cameraScrollXText),
                                scrollY: Double(cameraScrollYText),
                                zoom: Double(cameraZoomText)
                            )
                            try await requireCoordinator().setCamera(patch)
                            return "Applied camera patch."
                        }
                    }
                }

                debugCard("Scroll To Element", systemImage: "scope") {
                    TextField("Element ID, or leave empty to use current selection", text: $cameraElementID)
                        .textFieldStyle(.roundedBorder)

                    Picker("Mode", selection: $scrollMode) {
                        Text("Center").tag(ExcalidrawCore.ScrollToElementMode.center)
                        Text("Fit Content").tag(ExcalidrawCore.ScrollToElementMode.fitContent)
                        Text("Fit Viewport").tag(ExcalidrawCore.ScrollToElementMode.fitViewport)
                    }
                    .pickerStyle(.menu)

                    if scrollMode == .fitViewport {
                        compactField("viewportZoomFactor", text: $scrollViewportZoomFactorText)
                    }

                    HStack(spacing: 8) {
                        compactField("minZoom", text: $scrollMinZoomText)
                        compactField("maxZoom", text: $scrollMaxZoomText)
                    }

                    debugActionButton("Run Scroll") {
                        runCameraAction("Scroll To Element") {
                            let targetID = try resolvedTargetElementID()
                            try await requireCoordinator().scrollToElement(
                                id: targetID,
                                options: .init(
                                    mode: scrollMode,
                                    animate: true,
                                    duration: 300,
                                    viewportZoomFactor: scrollMode == .fitViewport ? Double(scrollViewportZoomFactorText) : nil,
                                    minZoom: Double(scrollMinZoomText),
                                    maxZoom: Double(scrollMaxZoomText)
                                )
                            )
                            return "Scrolled to \(targetID) using \(scrollMode.rawValue)."
                        }
                    }
                }

                debugCard("Zoom To Fit IDs", systemImage: "rectangle.inset.filled.and.person.filled") {
                    TextField("Comma-separated element IDs", text: $fitElementIDsText)
                        .textFieldStyle(.roundedBorder)
                    debugActionButton("Zoom To Fit IDs") {
                        runCameraAction("Zoom To Fit IDs") {
                            let ids = fitElementIDsText
                                .split(separator: ",")
                                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                                .filter { !$0.isEmpty }
                            try await requireCoordinator().zoomToFitElements(ids: ids)
                            return "Zoomed to fit \(ids.count) elements."
                        }
                    }
                }
            }
        } label: {
            Label("Camera", systemImage: "viewfinder")
                .font(.headline)
        }
    }

    @ViewBuilder
    private var adjustSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                statusBadge(isDryRun ? "Dry Run Enabled" : "Live Apply", systemImage: isDryRun ? "drop.triangle" : "bolt.fill")

                Toggle("Dry Run", isOn: $isDryRun)

                TextEditor(text: $adjustPayload)
                    .font(.system(.caption, design: .monospaced))
                    .frame(minHeight: 220)
                    .padding(6)
                    .background {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(.quaternary.opacity(0.12))
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(.quaternary)
                    }

                HStack(spacing: 10) {
                    debugActionButton("Run Adjust Tool") {
                        runAdjustTool()
                    }
                    .disabled(isRunning)

                    if isRunning {
                        ProgressView()
                            .controlSize(.small)
                    }
                }
            }
        } label: {
            Label("Adjust", systemImage: "slider.horizontal.3")
                .font(.headline)
        }
    }

    @ViewBuilder
    private var logsSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                if !lastError.isEmpty {
                    ScrollView {
                        Text(lastError)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                    .frame(minHeight: 80, maxHeight: 140)
                    .padding(8)
                    .background(.red.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }

                if !lastResult.isEmpty {
                    ScrollView {
                        Text(lastResult)
                            .font(.system(.caption, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                    .frame(minHeight: 80, maxHeight: 180)
                    .padding(8)
                    .background(.quaternary.opacity(0.4))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
        } label: {
            Label("Logs", systemImage: "text.alignleft")
                .font(.headline)
        }
    }

    @ViewBuilder
    private var debugHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Debug Console")
                .font(.title3.weight(.semibold))
            Text("Direct bridge controls for camera, element adjustment, and tool inspection.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private func debugActionButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .frame(maxWidth: .infinity)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
    }

    @ViewBuilder
    private func compactField(_ title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            TextField(title, text: text)
                .textFieldStyle(.roundedBorder)
        }
    }

    @ViewBuilder
    private func debugCard<Content: View>(
        _ title: String,
        systemImage: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: systemImage)
                .font(.subheadline.weight(.medium))
            content()
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.18), in: RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private func statusBadge(_ text: String, systemImage: String) -> some View {
        Label(text, systemImage: systemImage)
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.quaternary.opacity(0.18), in: Capsule())
            .lineLimit(1)
    }

    private func requireCoordinator() throws -> ExcalidrawCanvasView.Coordinator {
        guard let activeCoordinator else {
            struct MissingCoordinator: LocalizedError {
                var errorDescription: String? { "No active Excalidraw coordinator." }
            }
            throw MissingCoordinator()
        }
        return activeCoordinator
    }

    private func requireSelectionIDs() throws -> [String] {
        let ids = selectedElementIDs
        guard !ids.isEmpty else {
            struct MissingSelection: LocalizedError {
                var errorDescription: String? { "No selected elements." }
            }
            throw MissingSelection()
        }
        return ids
    }

    private func resolvedTargetElementID() throws -> String {
        let trimmedID = cameraElementID.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedID.isEmpty {
            return trimmedID
        }
        guard let selectedID = selectedElementIDs.first else {
            struct MissingElementTarget: LocalizedError {
                var errorDescription: String? { "Provide an element ID or select an element first." }
            }
            throw MissingElementTarget()
        }
        return selectedID
    }

    private func runCameraAction(
        _ title: String,
        action: @escaping @MainActor () async throws -> String
    ) {
        isRunning = true
        lastError = ""
        cameraDirector.suspend()
        Task {
            do {
                let result = try await action()
                await MainActor.run {
                    lastResult = "[\(title)]\n\(result)"
                    isRunning = false
                }
            } catch {
                await MainActor.run {
                    lastError = "[\(title)]\n\(error.localizedDescription)"
                    isRunning = false
                }
            }
        }
    }

    @MainActor
    private func syncCoordinatorRegistry() {
        ExcalidrawCoordinatorRegistry.shared.update(
            normal: fileState.excalidrawWebCoordinator,
            collaboration: fileState.excalidrawCollaborationWebCoordinator
        )
    }

    private func runTrackSelection() {
        isRunning = true
        lastError = ""

        Task {
            do {
                await MainActor.run {
                    syncCoordinatorRegistry()
                }
                let ids = try requireSelectionIDs()
                try await cameraDirector.submitElementIDs(ids, mode: .replace)
                await MainActor.run {
                    lastResult = "[Camera Director]\nSubmitted \(ids.count) selected element(s) to current session."
                    isRunning = false
                }
            } catch {
                await MainActor.run {
                    lastError = "[Camera Director]\n\(error.localizedDescription)"
                    isRunning = false
                }
            }
        }
    }

    private func runStagedDirectorDemo() {
        isRunning = true
        lastError = ""

        Task {
            do {
                let canvasTarget = await MainActor.run { () -> ExcalidrawCoordinatorRegistry.CanvasTarget in
                    syncCoordinatorRegistry()
                    return cameraTarget
                }
                let fileData = try await currentFileData
                let context = ExcalidrawChatInvocationContext(
                    currentFileData: fileData,
                    canvasTarget: canvasTarget
                )

                let tool = AdjustElementsTool()
                try await cameraDirector.beginSession()

                let payloads = [
                    """
                    {
                      "dryRun": false,
                      "ops": [
                        {
                          "op": "add",
                          "element": {
                            "type": "text",
                            "text": "Stage 1",
                            "x": 180,
                            "y": 220
                          }
                        },
                        {
                          "op": "add",
                          "element": {
                            "type": "rectangle",
                            "x": 120,
                            "y": 300,
                            "width": 180,
                            "height": 96
                          }
                        }
                      ]
                    }
                    """,
                    """
                    {
                      "dryRun": false,
                      "ops": [
                        {
                          "op": "add",
                          "element": {
                            "type": "text",
                            "text": "Stage 2",
                            "x": 760,
                            "y": 180
                          }
                        },
                        {
                          "op": "add",
                          "element": {
                            "type": "ellipse",
                            "x": 700,
                            "y": 290,
                            "width": 160,
                            "height": 110
                          }
                        }
                      ]
                    }
                    """,
                    """
                    {
                      "dryRun": false,
                      "ops": [
                        {
                          "op": "add",
                          "element": {
                            "type": "text",
                            "text": "Stage 3",
                            "x": 1260,
                            "y": 420
                          }
                        },
                        {
                          "op": "add",
                          "element": {
                            "type": "rectangle",
                            "x": 1180,
                            "y": 520,
                            "width": 220,
                            "height": 120
                          }
                        }
                      ]
                    }
                    """
                ]

                var lastStepResult = ""
                for (index, payload) in payloads.enumerated() {
                    let result = try await tool.execute(payload, context: context)
                    lastStepResult = Self.describeToolResult(result)
                    if index < payloads.count - 1 {
                        try await Task.sleep(nanoseconds: 850_000_000)
                    }
                }

                try await cameraDirector.endSession()

                await MainActor.run {
                    lastResult = "[Staged Director Demo]\nsteps=\(payloads.count)\n\(lastStepResult)"
                    isRunning = false
                }
            } catch {
                await MainActor.run {
                    lastError = "[Staged Director Demo]\n\(error.localizedDescription)"
                    isRunning = false
                }
            }
        }
    }

    private func runInspectFollow() {
        isRunning = true
        lastError = ""

        Task {
            do {
                await MainActor.run {
                    syncCoordinatorRegistry()
                }
                let coordinator = try requireCoordinator()
                let result = try await coordinator.webView.callAsyncJavaScript(
                    """
                    return JSON.stringify({
                      camera: excalidrawZHelper.getCamera(),
                      width: excalidrawZHelper._api?.getAppState()?.width,
                      height: excalidrawZHelper._api?.getAppState()?.height,
                      hasGetCommonBounds: !!excalidrawZHelper._getCommonBounds
                    });
                    """,
                    arguments: [:],
                    contentWorld: .page
                )
                let text = (result as? String) ?? String(describing: result)
                await MainActor.run {
                    lastResult = "[Inspect Follow]\\n\(text)"
                    isRunning = false
                }
            } catch {
                await MainActor.run {
                    lastError = "[Inspect Follow]\\n\(error.localizedDescription)"
                    isRunning = false
                }
            }
        }
    }

    private func runAdjustTool() {
        isRunning = true
        lastError = ""

        Task {
            do {
                await MainActor.run {
                    syncCoordinatorRegistry()
                }

                let payload = try withDryRunInjected(into: adjustPayload, dryRun: isDryRun)
                let tool = AdjustElementsTool()
                let fileData = try await currentFileData
                let context = ExcalidrawChatInvocationContext(
                    currentFileData: fileData,
                    canvasTarget: cameraTarget
                )
                let result = try await tool.execute(payload, context: context)
                let resultText = Self.describeToolResult(result)

                await MainActor.run {
                    lastResult = "[Adjust Tool]\n\(resultText)"
                    isRunning = false
                }
            } catch {
                await MainActor.run {
                    lastError = "[Adjust Tool]\n\(error.localizedDescription)"
                    isRunning = false
                }
            }
        }
    }

    private var currentFileData: Data? {
        get async throws {
            try await CurrentExcalidrawDataResolver.resolve(
                fileState: fileState,
                canvasTarget: cameraTarget
            )
        }
    }

    private func withDryRunInjected(into payload: String, dryRun: Bool) throws -> String {
        guard let data = payload.data(using: .utf8),
              var jsonObject = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            struct InvalidPayload: LocalizedError {
                var errorDescription: String? { "Payload must be a JSON object." }
            }
            throw InvalidPayload()
        }
        jsonObject["dryRun"] = dryRun
        let patchedData = try JSONSerialization.data(withJSONObject: jsonObject, options: [.prettyPrinted, .sortedKeys])
        return String(data: patchedData, encoding: .utf8) ?? payload
    }

    /// Flatten a `ToolResult` to plain text for the debug panel display.
    /// Image parts get a placeholder marker — this panel is text-only.
    static func describeToolResult(_ result: ToolResult) -> String {
        switch result {
            case .text(let text):
                return text
            case .parts(let parts):
                return parts.map { part -> String in
                    switch part {
                        case .text(let text): return text
                        case .image: return "<image>"
                    }
                }.joined(separator: "\n")
        }
    }
}

#endif
