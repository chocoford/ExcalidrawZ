#if os(macOS)
import AppKit
import ChocofordUI
import SwiftUI

struct ScreenAnnotationView: View {
    @ObservedObject var session: ScreenAnnotationSession
    @ObservedObject var saveConfiguration: ScreenAnnotationSaveConfiguration
    let tools: [ExcalidrawTool]
    let initialToolbarPlacement: ScreenAnnotationToolbarPlacement?
    let onToolbarPlacementChange: (ScreenAnnotationToolbarPlacement) -> Void
    let onToggleFreeze: () -> Void
    let onSave: (
        ScreenAnnotationSaveDestination,
        ScreenAnnotationSaveFormat,
        CGRect?,
        @MainActor @escaping () -> Void
    ) async -> Bool
    let onClose: () -> Void

    @State private var toolbarSize: CGSize = .zero
    @State private var toolbarCenter: CGPoint?
    @State private var toolbarDragStartCenter: CGPoint?
    @State private var isToolbarDragging = false
    @State private var isToolbarPresented = false
    @State private var toolbarToolRowSize = CGSize.zero
    @State private var isPropertiesPanelPresented = false
    @State private var propertiesPanelSize = CGSize(width: 300, height: 52)
    @State private var isFilePickerPresented = false
    @State private var captureScope = ScreenAnnotationCaptureScope.fullScreen
    @State private var captureRegion: CGRect?
    @State private var isCaptureChromeHidden = false
    @State private var isSaving = false

    private let defaultToolbarCenterDistanceFromBottom: CGFloat = 200
    private let toolbarEdgePadding: CGFloat = 12
    private let propertiesPanelEdgePadding: CGFloat = 12
    private let toolbarCoordinateSpace = "ScreenAnnotationToolbar"

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                frozenBackground

                ScreenAnnotationWebView(session: session)
                    .opacity(session.isReady ? 1 : 0)

                if isPropertiesPanelPresented, !isCaptureChromeHidden {
                    propertiesPanel
                        .readSize($propertiesPanelSize)
                        .position(
                            propertiesPanelCenter(in: proxy.size)
                        )
                        .transition(
                            .opacity.combined(with: .offset(y: 8))
                        )
                }

                if isToolbarPresented,
                   !isCaptureChromeHidden {
                    toolbar(containerSize: proxy.size)
                        .readSize($toolbarSize)
                        .position(resolvedToolbarCenter(in: proxy.size))
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
                            if isToolbarDragging {
                                transaction.animation = nil
                                transaction.disablesAnimations = true
                            }
                        }
                        .zIndex(2_000)
                }

                if !session.isReady {
                    loadingIndicator
                }

                if captureScope == .area, !isCaptureChromeHidden {
                    ScreenAnnotationCaptureRegionView(
                        containerSize: proxy.size,
                        initialSelection: captureRegion,
                        onSelectionChange: { region in
                            captureRegion = region
                        }
                    )
                    .transition(.opacity)
                    .zIndex(1_000)
                }
            }
            .coordinateSpace(name: toolbarCoordinateSpace)
            .animation(
                .easeOut(duration: 0.18),
                value: isPropertiesPanelPresented
            )
        }
        .ignoresSafeArea()
        .animation(.easeOut(duration: 0.18), value: session.isReady)
        .task(id: session.isReady) {
            guard session.isReady else {
                isToolbarPresented = false
                return
            }

            do {
                try await Task.sleep(nanoseconds: 250_000_000)
            } catch {
                return
            }

            withAnimation(.easeOut(duration: 0.3)) {
                isToolbarPresented = true
            }
        }
        .task(id: shouldShowPropertiesPanel) {
            guard shouldShowPropertiesPanel else {
                isPropertiesPanelPresented = false
                return
            }

            do {
                try await Task.sleep(nanoseconds: 120_000_000)
            } catch {
                return
            }
            guard shouldShowPropertiesPanel else { return }

            withAnimation(.easeOut(duration: 0.18)) {
                isPropertiesPanelPresented = true
            }
        }
        .sheet(isPresented: $isFilePickerPresented) {
            ExcalidrawFileBrowser { selection in
                switch selection {
                    case .file(let file):
                        saveConfiguration.selectFileDestination(
                            .libraryFile(
                                objectID: file.objectID,
                                name: file.name
                                    ?? String(localizable: .generalUnknown)
                            )
                        )
                    case .localFile(let url):
                        saveConfiguration.selectFileDestination(
                            .localFile(url: url)
                        )
                }
            }
        }
    }

    private var propertiesPanel: some View {
        ElementPropertiesPanel(
            properties: $session.selectedElementProperties,
            context: session.selectionContext ?? .mixed,
            onChange: session.applySelectedElementProperties
        )
    }

    private var shouldShowPropertiesPanel: Bool {
        session.selectionViewportBounds != nil
            && session.selectionContext != nil
            && !session.isCanvasInteractionActive
            && !session.isSelectionGeometryChanging
            && !session.isSelectionBoundsResolving
    }

    private func propertiesPanelCenter(in containerSize: CGSize) -> CGPoint {
        guard let selection = session.selectionViewportBounds else {
            return CGPoint(
                x: containerSize.width - propertiesPanelEdgePadding
                    - propertiesPanelSize.width / 2,
                y: containerSize.height / 2
            )
        }

        let halfWidth = propertiesPanelSize.width / 2
        let halfHeight = propertiesPanelSize.height / 2
        let spacing: CGFloat = 12
        let x = min(
            max(
                selection.midX,
                propertiesPanelEdgePadding + halfWidth
            ),
            containerSize.width - propertiesPanelEdgePadding - halfWidth
        )
        let topY = selection.minY - spacing - halfHeight
        let bottomY = selection.maxY + spacing + halfHeight
        let y = topY - halfHeight >= propertiesPanelEdgePadding
            ? topY
            : min(
                bottomY,
                containerSize.height - propertiesPanelEdgePadding - halfHeight
            )
        return CGPoint(x: x, y: y)
    }

    @ViewBuilder
    private var frozenBackground: some View {
        if let backgroundImage = session.frozenBackgroundImage {
            GeometryReader { proxy in
                Image(nsImage: backgroundImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .clipped()
            }
        }
    }

    private func toolbar(containerSize: CGSize) -> some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Button {
                    session.toggleToolLock()
                } label: {
                    let image = Image(
                        systemName: session.isToolLocked ? "lock.fill" : "lock.open"
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
            .readSize($toolbarToolRowSize)

            HStack(spacing: 8) {
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 20, weight: .semibold))
                        .symbolRenderingMode(.monochrome)
                        .foregroundStyle(.primary)
                }
                .buttonStyle(.borderless)
                .help("Exit screen annotation")

                Button {
                    session.undo()
                } label: {
                    Image(systemName: "arrow.uturn.backward")
                }
                .help("Undo")
                .modernButtonStyle(style: .glass, size: .large, shape: .circle)

                Button {
                    session.redo()
                } label: {
                    Image(systemName: "arrow.uturn.forward")
                }
                .help("Redo")
                .modernButtonStyle(style: .glass, size: .large, shape: .circle)

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
                            ? "Saving annotation"
                            : "Save to \(saveConfiguration.title)"
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
                .gesture(toolbarDragGesture(in: containerSize))

                ScreenAnnotationSaveControls(
                    configuration: saveConfiguration,
                    isFilePickerPresented: $isFilePickerPresented,
                    captureScope: $captureScope,
                    isSaving: isSaving,
                    canSave: captureScope == .fullScreen
                        || captureRegion != nil,
                    onSave: {
                        save(
                            region: captureScope == .area
                                ? captureRegion
                                : nil
                        )
                    }
                )
            }
            .frame(
                width: toolbarToolRowSize.width > 0
                    ? toolbarToolRowSize.width
                    : nil
            )
        }
        .padding(8)
        .background {
            toolbarBackground
                .contentShape(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                )
                .gesture(toolbarDragGesture(in: containerSize))
        }
        .shadow(color: .black.opacity(0.16), radius: 18, y: 8)
    }

    private func save(region: CGRect?) {
        guard !isSaving else { return }
        isSaving = true
        isCaptureChromeHidden = true

        Task { @MainActor in
            await Task.yield()
            try? await Task.sleep(nanoseconds: 80_000_000)
            let didSave = await onSave(
                saveConfiguration.destination,
                saveConfiguration.format,
                region,
                {
                    isCaptureChromeHidden = false
                }
            )
            guard !didSave else {
                onClose()
                return
            }
            isSaving = false
        }
    }

    private func toolbarDragGesture(in containerSize: CGSize) -> some Gesture {
        DragGesture(
            minimumDistance: 2,
            coordinateSpace: .named(toolbarCoordinateSpace)
        )
        .onChanged { value in
            if toolbarDragStartCenter == nil {
                isToolbarDragging = true
                toolbarDragStartCenter = resolvedToolbarCenter(in: containerSize)
            }
            guard let toolbarDragStartCenter else { return }
            let proposedCenter = CGPoint(
                x: toolbarDragStartCenter.x + value.translation.width,
                y: toolbarDragStartCenter.y + value.translation.height
            )
            toolbarCenter = clampedToolbarCenter(
                proposedCenter,
                in: containerSize
            )
        }
        .onEnded { _ in
            toolbarDragStartCenter = nil
            isToolbarDragging = false
            if let toolbarCenter {
                onToolbarPlacementChange(
                    ScreenAnnotationToolbarPlacement(
                        center: toolbarCenter,
                        containerSize: containerSize
                    )
                )
            }
        }
    }

    private func resolvedToolbarCenter(in containerSize: CGSize) -> CGPoint {
        let center = toolbarCenter
            ?? initialToolbarPlacement?.center(in: containerSize)
            ?? CGPoint(
                x: containerSize.width / 2,
                y: containerSize.height
                    - defaultToolbarCenterDistanceFromBottom
            )
        return clampedToolbarCenter(center, in: containerSize)
    }

    private func clampedToolbarCenter(
        _ center: CGPoint,
        in containerSize: CGSize
    ) -> CGPoint {
        let halfWidth = toolbarSize.width / 2
        let halfHeight = toolbarSize.height / 2
        let minX = toolbarEdgePadding + halfWidth
        let maxX = containerSize.width - toolbarEdgePadding - halfWidth
        let minY = toolbarEdgePadding + halfHeight
        let maxY = containerSize.height - toolbarEdgePadding - halfHeight

        return CGPoint(
            x: minX <= maxX ? min(max(center.x, minX), maxX) : containerSize.width / 2,
            y: minY <= maxY ? min(max(center.y, minY), maxY) : containerSize.height / 2
        )
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
                    in: RoundedRectangle(cornerRadius: 20, style: .continuous)
                )
        } else {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.regularMaterial)
        }
    }

    private var loadingIndicator: some View {
        VStack(spacing: 10) {
            if let errorMessage = session.errorMessage {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text(errorMessage)
                    .font(.callout)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 320)
            } else {
                ProgressView()
                    .controlSize(.large)
                Text("Preparing annotation canvas")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(20)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
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
