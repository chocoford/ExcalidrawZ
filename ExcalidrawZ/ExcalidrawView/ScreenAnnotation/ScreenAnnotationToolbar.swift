#if os(macOS)
import ChocofordUI
import SwiftUI

struct ScreenAnnotationToolbar: View {
    static let coordinateSpaceName = "ScreenAnnotationToolbar"

    @ObservedObject var session: ScreenAnnotationSession
    @ObservedObject var saveConfiguration: ScreenAnnotationSaveConfiguration
    @Binding var isFilePickerPresented: Bool
    @Binding var captureScope: ScreenAnnotationCaptureScope

    let tools: [ExcalidrawTool]
    let containerSize: CGSize
    let initialPlacement: ScreenAnnotationToolbarPlacement?
    let isSaving: Bool
    let canSave: Bool
    let onPlacementChange: (ScreenAnnotationToolbarPlacement) -> Void
    let onToggleFreeze: () -> Void
    let onSave: () -> Void
    let onClose: () -> Void

    @State private var size = CGSize.zero
    @State private var center: CGPoint?
    @State private var dragStartCenter: CGPoint?
    @State private var isDragging = false
    @State private var toolRowSize = CGSize.zero

    private let defaultCenterDistanceFromBottom: CGFloat = 200
    private let edgePadding: CGFloat = 12

    var body: some View {
        content
            .readSize($size)
            .position(resolvedCenter)
            .transition(
                .modifier(
                    active: ScreenAnnotationToolbarRevealModifier(
                        opacity: 0,
                        blurRadius: 12
                    ),
                    identity: ScreenAnnotationToolbarRevealModifier(
                        opacity: 1,
                        blurRadius: 0
                    )
                )
            )
            .transaction { transaction in
                if isDragging {
                    transaction.animation = nil
                    transaction.disablesAnimations = true
                }
            }
    }

    private var content: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Button {
                    session.toggleToolLock()
                } label: {
                    let image = Image(
                        systemName: session.isToolLocked
                            ? "lock.fill"
                            : "lock.open"
                    )
                    if #available(macOS 14.0, *) {
                        image.contentTransition(.symbolEffect(.replace))
                    } else {
                        image
                    }
                }
                .help(String(localizable: .toolbarButtonLockToolHelp))
                .modernButtonStyle(
                    style: session.isToolLocked ? .glassProminent : .glass,
                    size: .large,
                    shape: .circle
                )

                SegmentedPicker(selection: selectedToolBinding) {
                    ForEach(tools, id: \.self) { tool in
                        let shortcutLabel = toolbarToolOrder.shortcutLabel(
                            for: tool
                        )
                        SegmentedPickerItem(value: tool) {
                            ScreenAnnotationToolPickerItem(
                                tool: tool,
                                shortcutLabel: shortcutLabel
                            )
                        }
                        .help(tool.help(shortcutLabel: shortcutLabel))
                    }
                }
            }
            .readSize($toolRowSize)

            HStack(spacing: 8) {
                closeButton
                undoButton
                redoButton
                freezeButton
                saveStatus

                ScreenAnnotationSaveControls(
                    configuration: saveConfiguration,
                    isFilePickerPresented: $isFilePickerPresented,
                    captureScope: $captureScope,
                    isSaving: isSaving,
                    canSave: canSave,
                    onSave: onSave
                )
            }
            .frame(width: toolRowSize.width > 0 ? toolRowSize.width : nil)
        }
        .padding(8)
        .background {
            toolbarBackground
                .contentShape(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                )
                .gesture(dragGesture)
        }
        .shadow(color: .black.opacity(0.16), radius: 18, y: 8)
    }

    private var closeButton: some View {
        Button(action: onClose) {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 20, weight: .semibold))
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(.primary)
        }
        .buttonStyle(.borderless)
        .help("Exit screen annotation")
    }

    private var undoButton: some View {
        Button {
            session.undo()
        } label: {
            Image(systemName: "arrow.uturn.backward")
        }
        .help("Undo")
        .modernButtonStyle(style: .glass, size: .large, shape: .circle)
    }

    private var redoButton: some View {
        Button {
            session.redo()
        } label: {
            Image(systemName: "arrow.uturn.forward")
        }
        .help("Redo")
        .modernButtonStyle(style: .glass, size: .large, shape: .circle)
    }

    private var freezeButton: some View {
        Button(action: onToggleFreeze) {
            if session.isCapturingBackground {
                ProgressView()
                    .controlSize(.small)
                    .frame(width: 16, height: 16)
            } else {
                let image = Image(
                    systemName: session.isFrozen
                        ? "livephoto"
                        : "camera.viewfinder"
                )
                if #available(macOS 14.0, *) {
                    image.contentTransition(.symbolEffect(.replace))
                } else {
                    image
                }
            }
        }
        .help(session.isFrozen ? "Resume live screen" : "Freeze screen")
        .disabled(session.isCapturingBackground)
        .modernButtonStyle(
            style: session.isFrozen ? .glassProminent : .glass,
            size: .large,
            shape: .circle
        )
    }

    private var saveStatus: some View {
        HStack(spacing: 6) {
            if isSaving {
                ProgressView()
                    .controlSize(.small)
            } else {
                Image(systemName: "info.circle.fill")
                    .symbolRenderingMode(.hierarchical)
            }

            Text(
                isSaving
                    ? "Saving \(saveConfiguration.format.title)"
                    : "Save to \(saveConfiguration.title) as \(saveConfiguration.format.title)"
            )
            .font(.callout)
            .lineLimit(1)
            .truncationMode(.middle)
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity)
        .background {
            if #available(macOS 26.0, *) {
                Capsule()
                    .fill(.clear)
                    .glassEffect(.regular, in: Capsule())
            } else {
                Capsule()
                    .fill(.regularMaterial)
            }
        }
        .shadow(color: .black.opacity(0.18), radius: 8, y: 4)
        .contentShape(Capsule())
        .gesture(dragGesture)
    }

    private var selectedToolBinding: Binding<ExcalidrawTool?> {
        Binding {
            session.selectedTool
        } set: { tool in
            if let tool {
                session.select(tool)
            }
        }
    }

    private var toolbarToolOrder: ExcalidrawToolbarToolOrder {
        ExcalidrawToolbarToolOrder(tools: tools)
    }

    @ViewBuilder
    private var toolbarBackground: some View {
        if #available(macOS 26.0, *) {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.clear)
                .glassEffect(
                    .regular,
                    in: RoundedRectangle(
                        cornerRadius: 20,
                        style: .continuous
                    )
                )
        } else {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.regularMaterial)
        }
    }

    private var dragGesture: some Gesture {
        DragGesture(
            minimumDistance: 2,
            coordinateSpace: .named(Self.coordinateSpaceName)
        )
        .onChanged { value in
            if dragStartCenter == nil {
                isDragging = true
                dragStartCenter = resolvedCenter
            }
            guard let dragStartCenter else { return }
            let proposedCenter = CGPoint(
                x: dragStartCenter.x + value.translation.width,
                y: dragStartCenter.y + value.translation.height
            )
            center = clampedCenter(proposedCenter)
        }
        .onEnded { _ in
            dragStartCenter = nil
            isDragging = false
            if let center {
                onPlacementChange(
                    ScreenAnnotationToolbarPlacement(
                        center: center,
                        containerSize: containerSize
                    )
                )
            }
        }
    }

    private var resolvedCenter: CGPoint {
        let center = self.center
            ?? initialPlacement?.center(in: containerSize)
            ?? CGPoint(
                x: containerSize.width / 2,
                y: containerSize.height - defaultCenterDistanceFromBottom
            )
        return clampedCenter(center)
    }

    private func clampedCenter(_ center: CGPoint) -> CGPoint {
        let halfWidth = size.width / 2
        let halfHeight = size.height / 2
        let minX = edgePadding + halfWidth
        let maxX = containerSize.width - edgePadding - halfWidth
        let minY = edgePadding + halfHeight
        let maxY = containerSize.height - edgePadding - halfHeight

        return CGPoint(
            x: minX <= maxX
                ? min(max(center.x, minX), maxX)
                : containerSize.width / 2,
            y: minY <= maxY
                ? min(max(center.y, minY), maxY)
                : containerSize.height / 2
        )
    }
}

private struct ScreenAnnotationToolbarRevealModifier: ViewModifier {
    let opacity: Double
    let blurRadius: CGFloat

    func body(content: Content) -> some View {
        content
            .opacity(opacity)
            .blur(radius: blurRadius)
    }
}

private struct ScreenAnnotationToolPickerItem: View {
    let tool: ExcalidrawTool
    let shortcutLabel: String?

    private let size: CGFloat = 20

    private var labelType: ExcalidrawToolbarItemModifer.LabelType {
        switch tool {
            case .rectangle, .diamond, .ellipse, .line:
                .nativeShape
            case .cursor:
                .svg
            default:
                .image
        }
    }

    var body: some View {
        tool.icon()
            .modifier(
                ExcalidrawToolbarItemModifer(
                    size: size,
                    labelType: labelType
                ) {
                    if let shortcutLabel {
                        Text(shortcutLabel)
                    }
                }
            )
    }
}
#endif
