//
//  ViewerEditorControls.swift
//  ExcalidrawZ
//

#if os(macOS)
import SwiftUI

/// Controls Viewer from the presenter's editor, keeping the audience window clean.
struct ViewerEditorControls: View {
    @ObservedObject private var controller = ViewerMirrorController.shared

    var body: some View {
        if let session = controller.session {
            ViewerFloatingToolbar(controller: controller, session: session)
        }
    }
}

private struct ViewerFloatingToolbar: View {
    private enum DisplayMode {
        case dense
        case full
    }

    private enum Control: Hashable {
        case follow
        case pointer
        case color
        case expansion
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject var controller: ViewerMirrorController
    @ObservedObject var session: ViewerMirrorSession

    @State private var displayMode: DisplayMode = .dense
    @State private var isShowingColorSettings = false

    private var isDense: Bool { displayMode == .dense }

    private var cornerRadius: CGFloat {
        isDense ? ViewerControlMetrics.iconSize / 2 + ViewerControlMetrics.densePadding : 20
    }

    private var controlsLayout: AnyLayout {
        isDense
            ? AnyLayout(HStackLayout(spacing: 6))
            : AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
    }

    private var controlOrder: [Control] {
        isDense
            ? [.follow, .pointer, .color, .expansion]
            : [.expansion, .follow, .pointer, .color]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: isDense ? 0 : 12) {
            controlsLayout {
                // Stable IDs preserve each control while the layout and order change.
                ForEach(controlOrder, id: \.self) { control in
                    switch control {
                        case .follow:
                            followControl
                        case .pointer:
                            pointerControl
                        case .color:
                            colorControl
                        case .expansion:
                            expansionControl
                    }
                }
            }

            if !session.supportsPointerAppearance {
                Text(localizable: .viewerPointerSettingsUnavailable)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(width: isDense ? 0 : ViewerControlMetrics.expandedWidth,
                           height: isDense ? 0 : nil, alignment: .leading)
                    .opacity(isDense ? 0 : 1)
                    .accessibilityHidden(isDense)
            }
        }
        .frame(height: isDense ? ViewerControlMetrics.iconSize : nil)
        .buttonStyle(.borderless)
        .padding(isDense ? ViewerControlMetrics.densePadding : 16)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .background { toolbarBackground }
        .overlay {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
        }
        .shadow(color: .black.opacity(0.16), radius: 12, y: 4)
    }

    private var followControl: some View {
        ViewerControlToggleRow(
            title: String(localizable: .viewerFollowCanvas), symbol: "viewfinder",
            isDense: isDense, isOn: $controller.isFollowingCamera
        )
        .help(String(localizable: .viewerFollowCanvas))
    }

    private var pointerControl: some View {
        ViewerControlToggleRow(
            title: String(localizable: .viewerShowPointer), symbol: "cursorarrow.rays",
            isDense: isDense, isOn: $controller.pointerAppearance.isVisible
        )
        .disabled(!session.supportsPointerAppearance)
        .help(String(localizable: .viewerShowPointer))
    }

    private var colorControl: some View {
        ZStack(alignment: .leading) {
            Button {
                isShowingColorSettings.toggle()
            } label: {
                Label(String(localizable: .viewerPointerColor), systemImage: "paintpalette")
                    .labelStyle(.iconOnly)
                    .frame(width: ViewerControlMetrics.iconSize, height: ViewerControlMetrics.iconSize)
            }
            .opacity(isDense ? 1 : 0)
            .disabled(!isDense)
            .allowsHitTesting(isDense)
            .accessibilityHidden(!isDense)
            .help(String(localizable: .viewerPointerColor))
            .popover(isPresented: $isShowingColorSettings, arrowEdge: .bottom) {
                colorSettings
                    .controlSize(.small)
                    .padding(16)
            }

            colorSettings
                .disabled(isDense)
                .frame(height: isDense ? 0 : nil)
                .opacity(isDense ? 0 : 1)
                .allowsHitTesting(!isDense)
                .accessibilityHidden(isDense)
        }
        .frame(width: isDense ? ViewerControlMetrics.iconSize : ViewerControlMetrics.expandedWidth,
               height: isDense ? ViewerControlMetrics.iconSize : nil, alignment: .leading)
        .disabled(!session.supportsPointerAppearance || !controller.pointerAppearance.isVisible)
    }

    private var expansionControl: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Text(localizable: .viewerWindowTitle)
                    .font(.headline)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .frame(width: isDense ? 0 : nil, alignment: .leading)
                    .opacity(isDense ? 0 : 1)
                    .accessibilityHidden(isDense)
                Spacer(minLength: 0)
                Button { setDisplayMode(isDense ? .full : .dense) } label: {
                    Image(systemName: "chevron.up")
                        .rotationEffect(.degrees(isDense ? 0 : 180))
                        .frame(width: ViewerControlMetrics.iconSize, height: ViewerControlMetrics.iconSize)
                }
                .accessibilityLabel(Text(expansionLabel))
                .help(expansionLabel)
            }
            .frame(height: ViewerControlMetrics.iconSize)

            Divider()
                .frame(height: isDense ? 0 : 1)
                .padding(.top, isDense ? 0 : 8)
                .opacity(isDense ? 0 : 1)
        }
        .frame(width: isDense ? ViewerControlMetrics.iconSize : ViewerControlMetrics.expandedWidth)
    }

    private var expansionLabel: String {
        isDense
            ? String(localizable: .viewerExpandControls)
            : String(localizable: .viewerCollapseControls)
    }

    private var colorSettings: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(localizable: .viewerPointerColor)
            ColorButtonGroup(
                colors: ColorPalette.collaboratorQuickPicks,
                selectedColor: controller.pointerAppearance.colorHex ?? ViewerPointerAppearance.defaultColorHex,
                supportsOpacity: false,
                adaptsToDarkMode: false
            ) { color in
                guard let hex = ViewerPointerAppearance.normalizedColorHex(color) else { return }
                controller.pointerAppearance.colorHex = hex
            }
            .accessibilityLabel(Text(localizable: .viewerPointerColor))
        }
        .frame(width: ViewerControlMetrics.expandedWidth, alignment: .leading)
    }

    private func setDisplayMode(_ mode: DisplayMode) {
        isShowingColorSettings = false
        withAnimation(reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.9)) {
            displayMode = mode
        }
    }

    @ViewBuilder
    private var toolbarBackground: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        if #available(macOS 26.0, *) {
            shape.fill(.clear)
                .glassEffect(.regular, in: shape)
        } else {
            shape.fill(.regularMaterial)
        }
    }
}

private enum ViewerControlMetrics {
    static let iconSize: CGFloat = 32
    static let densePadding: CGFloat = 6
    static let expandedWidth: CGFloat = 260
}

/// Both toggle presentations stay mounted while their row moves in AnyLayout.
private struct ViewerControlToggleRow: View {
    @Environment(\.isEnabled) private var isEnabled

    let title: String
    let symbol: String
    let isDense: Bool
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 0) {
            Text(title)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .frame(width: isDense ? 0 : nil, alignment: .leading)
                .opacity(isDense ? 0 : 1)
                .accessibilityHidden(true)

            Spacer(minLength: isDense ? 0 : 12)

            ZStack {
                Toggle(isOn: $isOn) {
                    Image(systemName: symbol)
                        .frame(width: ViewerControlMetrics.iconSize, height: ViewerControlMetrics.iconSize)
                }
                .toggleStyle(.button)
                .foregroundStyle(isEnabled && isOn ? Color.accentColor : Color.secondary)
                .accessibilityLabel(Text(title))
                .opacity(isDense ? 1 : 0)
                .disabled(!isDense)
                .allowsHitTesting(isDense)
                .accessibilityHidden(!isDense)

                Toggle(title, isOn: $isOn)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .fixedSize()
                    .opacity(isDense ? 0 : 1)
                    .disabled(isDense)
                    .allowsHitTesting(!isDense)
                    .accessibilityHidden(isDense)
            }
            .frame(width: isDense ? ViewerControlMetrics.iconSize : nil,
                   height: ViewerControlMetrics.iconSize)
        }
        .frame(width: isDense ? ViewerControlMetrics.iconSize : ViewerControlMetrics.expandedWidth,
               height: ViewerControlMetrics.iconSize)
    }
}
#endif
