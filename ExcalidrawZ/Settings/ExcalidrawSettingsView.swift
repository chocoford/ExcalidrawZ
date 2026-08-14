//
//  ExcalidrawSettingsView.swift
//  ExcalidrawZ
//
//  Created by Chocoford on 1/4/26.
//

import SwiftUI
import ChocofordUI
import SFSafeSymbols
import UniformTypeIdentifiers

private let toolbarToolOrderApplyDebounceNanoseconds: UInt64 = 700_000_000

struct ExcalidrawSettingsView: View {
    @EnvironmentObject private var appPreference: AppPreference
    @State private var editingSettings: UserDrawingSettings = UserDrawingSettings()
    @State private var editingToolbarToolOrder = ExcalidrawToolbarToolOrder()
    @State private var draggingToolbarTool: ExcalidrawTool?
    @State private var toolbarToolOrderApplyTask: Task<Void, Never>?
#if os(iOS)
    @State private var toolbarToolOrderEditMode: EditMode = .active
#endif

    var body: some View {
#if os(iOS)
        settingsForm
            .environment(\.editMode, $toolbarToolOrderEditMode)
#else
        settingsForm
#endif
    }

    private var settingsForm: some View {
        SettingsFormContainer {
            content()
        }
        .onAppear {
            loadSettings()
        }
        .onDisappear {
            applyToolbarToolOrderNow(editingToolbarToolOrder)
        }
    }

    private func loadSettings() {
        editingSettings = appPreference.customDrawingSettings
        editingToolbarToolOrder = appPreference.toolbarToolOrder
    }

    private func saveSettings() {
        appPreference.customDrawingSettings = editingSettings
    }

    private func saveToolbarToolOrder(_ order: ExcalidrawToolbarToolOrder? = nil) {
        appPreference.toolbarToolOrder = order ?? editingToolbarToolOrder
    }
    
    @ViewBuilder
    private func content() -> some View {
        toolbarOrderSection()
        customDrawingSettingsSection()
    }

    @ViewBuilder
    private func toolbarOrderSection() -> some View {
        Section {
#if os(iOS)
            ForEach(editingToolbarToolOrder.tools, id: \.self) { tool in
                ToolbarToolOrderRow(
                    tool: tool,
                    shortcutLabel: editingToolbarToolOrder.shortcutLabel(for: tool),
                    showsDragHandle: false
                )
            }
            .onMove(perform: moveToolbarTools)
#else
            ForEach(editingToolbarToolOrder.tools, id: \.self) { tool in
                ToolbarToolOrderRow(
                    tool: tool,
                    shortcutLabel: editingToolbarToolOrder.shortcutLabel(for: tool),
                    showsDragHandle: true
                )
                .onDrag {
                    draggingToolbarTool = tool
                    return NSItemProvider(object: tool.toolbarOrderID as NSString)
                } preview: {
                    ToolbarToolOrderDragPreview(
                        tool: tool,
                        shortcutLabel: editingToolbarToolOrder.shortcutLabel(for: tool)
                    )
                }
                .onDrop(
                    of: [.plainText],
                    delegate: ToolbarToolOrderDropDelegate(
                        destinationTool: tool,
                        order: $editingToolbarToolOrder,
                        draggingTool: $draggingToolbarTool,
                        onUpdate: scheduleToolbarToolOrderApply,
                        onCommit: finishToolbarToolOrderDrag
                    )
                )
            }
            .onDrop(
                of: [.plainText],
                delegate: ToolbarToolOrderCommitDropDelegate(
                    draggingTool: $draggingToolbarTool,
                    onCommit: finishToolbarToolOrderDrag
                )
            )
#endif
        } header: {
            HStack {
                Text(localizable: .settingsExcalidrawToolbarOrderTitle)

                Spacer()

                Button {
                    let defaultOrder = ExcalidrawToolbarToolOrder()
                    draggingToolbarTool = nil
                    cancelToolbarToolOrderApply()
                    withAnimation(.smooth) {
                        editingToolbarToolOrder = defaultOrder
                    }
                    applyToolbarToolOrderNow(defaultOrder)
                } label: {
                    Label(.localizable(.generalButtonReset), systemSymbol: .arrowCounterclockwise)
                }
            }
        } footer: {
            Text(localizable: .settingsExcalidrawToolbarOrderFooter)
        }
    }

#if os(iOS)
    private func moveToolbarTools(from offsets: IndexSet, to destination: Int) {
        var updatedOrder = editingToolbarToolOrder
        updatedOrder.move(from: offsets, to: destination)
        withAnimation(.smooth) {
            editingToolbarToolOrder = updatedOrder
        }
        applyToolbarToolOrderNow(updatedOrder)
    }
#endif

    private func finishToolbarToolOrderDrag() {
        draggingToolbarTool = nil
        applyToolbarToolOrderNow(editingToolbarToolOrder)
    }

    private func scheduleToolbarToolOrderApply(_ order: ExcalidrawToolbarToolOrder) {
        toolbarToolOrderApplyTask?.cancel()
        toolbarToolOrderApplyTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: toolbarToolOrderApplyDebounceNanoseconds)

            guard !Task.isCancelled else {
                return
            }

            saveToolbarToolOrder(order)
            toolbarToolOrderApplyTask = nil
        }
    }

    private func applyToolbarToolOrderNow(_ order: ExcalidrawToolbarToolOrder) {
        cancelToolbarToolOrderApply()
        saveToolbarToolOrder(order)
    }

    private func cancelToolbarToolOrderApply() {
        toolbarToolOrderApplyTask?.cancel()
        toolbarToolOrderApplyTask = nil
    }

    @ViewBuilder
    private func customDrawingSettingsSection() -> some View {
        Section {
            HStack {
                VStack(alignment: .leading) {
                    HStack(spacing: 8) {
                        Button {
                            NotificationCenter.default.post(.captureCurrentDrawingSettings())
                            Task {
                                loadSettings()

                                try? await Task.sleep(nanoseconds: UInt64(1e+9 * 0.3))

                                loadSettings()

                                try? await Task.sleep(nanoseconds: UInt64(1e+9 * 0.5))

                                loadSettings()
                            }
                        } label: {
                            Label(.localizable(.settingsExcalidrawButtonCaptureCurrentSettings), systemSymbol: .arrowDownCircle)
                        }
                        .buttonStyle(.bordered)

                        Button {
                            editingSettings = UserDrawingSettings()
                            saveSettings()
                        } label: {
                            Label(.localizable(.generalButtonReset), systemSymbol: .arrowCounterclockwise)
                        }
                        .buttonStyle(.bordered)
                    }
                    .modernButtonStyle(style: .glass, shape: .modern)

                    DrawingSettingsPanel(
                        settings: $editingSettings,
                        onSettingsChange: saveSettings
                    )
                    .padding(.horizontal, 12)
                    .frame(width: 260, alignment: .leading)
                }
                Spacer(minLength: 0)
            }
        } header: {
            Text(localizable: .settingsExcalidrawDrawingSettingsTitle)
        } footer: {
            HStack {
                Spacer()
                Text("These defaults apply to new canvases. Override per canvas from the Preferences inspector.")
                    .foregroundStyle(.secondary)
            }
        }
    }

}

#Preview {
    ExcalidrawSettingsView()
        .environmentObject(AppPreference())
}

private struct ToolbarToolOrderRow: View {
    let tool: ExcalidrawTool
    let shortcutLabel: String?
    let showsDragHandle: Bool

    var body: some View {
        toolbarToolOrderRowContent(
            tool: tool,
            shortcutLabel: shortcutLabel,
            showsDragHandle: showsDragHandle
        )
    }
}

private struct ToolbarToolOrderDragPreview: View {
    let tool: ExcalidrawTool
    let shortcutLabel: String?

    var body: some View {
        toolbarToolOrderRowContent(
            tool: tool,
            shortcutLabel: shortcutLabel,
            showsDragHandle: false
        )
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
    }
}

@ViewBuilder
private func toolbarToolOrderRowContent(
    tool: ExcalidrawTool,
    shortcutLabel: String?,
    showsDragHandle: Bool
) -> some View {
    HStack(spacing: 10) {
        if showsDragHandle {
            Image(systemSymbol: .line3Horizontal)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
                .frame(width: 18)
        }

        tool.icon(strokeLineWidth: 1.8)
            .frame(width: 20, height: 20)

        Text(tool.localization)

        Spacer(minLength: 12)

        if let shortcutLabel {
            Text(shortcutLabel)
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(minWidth: 22)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(.quaternary, in: Capsule())
        }
    }
    .padding(.vertical, 4)
    .contentShape(Rectangle())
}

private struct ToolbarToolOrderDropDelegate: DropDelegate {
    let destinationTool: ExcalidrawTool
    @Binding var order: ExcalidrawToolbarToolOrder
    @Binding var draggingTool: ExcalidrawTool?
    let onUpdate: (ExcalidrawToolbarToolOrder) -> Void
    let onCommit: () -> Void

    func dropEntered(info: DropInfo) {
        guard let draggingTool,
              draggingTool != destinationTool,
              let fromIndex = order.tools.firstIndex(of: draggingTool),
              let toIndex = order.tools.firstIndex(of: destinationTool) else {
            return
        }

        withAnimation(.smooth) {
            order.move(
                from: IndexSet(integer: fromIndex),
                to: toIndex > fromIndex ? toIndex + 1 : toIndex
            )
        }
        onUpdate(order)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        onCommit()
        return true
    }
}

private struct ToolbarToolOrderCommitDropDelegate: DropDelegate {
    @Binding var draggingTool: ExcalidrawTool?
    let onCommit: () -> Void

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        onCommit()
        return true
    }
}
