#if os(macOS)
import AppKit
import ChocofordUI
import SwiftUI

struct ScreenAnnotationView: View {
    @ObservedObject var session: ScreenAnnotationSession
    @ObservedObject var saveConfiguration: ScreenAnnotationSaveConfiguration
    let webRuntime: ScreenAnnotationWebRuntime
    let tools: [ExcalidrawTool]
    let initialToolbarPlacement: ScreenAnnotationToolbarPlacement?
    let onToolbarPlacementChange: (ScreenAnnotationToolbarPlacement) -> Void
    let onToggleFreeze: () -> Void
    let onSave: (
        ScreenAnnotationSaveDestination,
        ScreenAnnotationSaveFormat,
        ScreenAnnotationImageQuality,
        CGRect?,
        @MainActor @escaping (Bool) -> Void
    ) -> Void
    let onClose: () -> Void

    @State private var isToolbarPresented = false
    @State private var isPropertiesPanelPresented = false
    @State private var isPropertiesPopoverPresented = false
    @State private var retainedSelectionViewportBounds: CGRect?
    @State private var retainedSelectionContext: ElementPropertiesContext?
    @State private var propertiesPanelSize = CGSize(width: 300, height: 52)
    @State private var isFilePickerPresented = false
    @State private var captureScope = ScreenAnnotationCaptureScope.fullScreen
    @State private var captureRegion: CGRect?
    @State private var isCaptureChromeHidden = false
    @State private var isSaving = false

    private let propertiesPanelEdgePadding: CGFloat = 12
    private let propertiesPanelSelectionSpacing: CGFloat = 40
    private let propertiesPanelDismissalDelay: UInt64 = 200_000_000

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                frozenBackground

                ScreenAnnotationWebView(
                    session: session,
                    runtime: webRuntime
                )
                    .opacity(session.isReady ? 1 : 0)

                if isPropertiesPopoverPresented {
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture {}
                        .zIndex(10)
                }

                if isPropertiesPanelPresented, !isCaptureChromeHidden {
                    propertiesPanel
                        .readSize($propertiesPanelSize)
                        .position(
                            propertiesPanelCenter(in: proxy.size)
                        )
                        .transition(
                            .opacity.combined(with: .offset(y: 8))
                        )
                        .zIndex(20)
                }

                if isToolbarPresented,
                   !isCaptureChromeHidden {
                    ScreenAnnotationToolbar(
                        session: session,
                        saveConfiguration: saveConfiguration,
                        isFilePickerPresented: $isFilePickerPresented,
                        captureScope: $captureScope,
                        tools: tools,
                        containerSize: proxy.size,
                        initialPlacement: initialToolbarPlacement,
                        isSaving: isSaving,
                        canSave: canSave,
                        onPlacementChange: onToolbarPlacementChange,
                        onToggleFreeze: onToggleFreeze,
                        onSave: {
                            save(
                                region: captureScope == .area
                                    ? captureRegion
                                    : nil
                            )
                        },
                        onClose: onClose
                    )
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
            .coordinateSpace(name: ScreenAnnotationToolbar.coordinateSpaceName)
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
                let needsPopoverDismissal = isPropertiesPopoverPresented
                isPropertiesPopoverPresented = false

                if needsPopoverDismissal {
                    do {
                        try await Task.sleep(
                            nanoseconds: propertiesPanelDismissalDelay
                        )
                    } catch {
                        return
                    }
                }

                guard !shouldShowPropertiesPanel else { return }
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
        .task(id: session.selectionViewportBounds) {
            if let selectionViewportBounds = session.selectionViewportBounds {
                retainedSelectionViewportBounds = selectionViewportBounds
            }
        }
        .task(id: session.selectionContext) {
            if let selectionContext = session.selectionContext {
                retainedSelectionContext = selectionContext
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
            isPopoverPresented: $isPropertiesPopoverPresented,
            context: session.selectionContext
                ?? retainedSelectionContext
                ?? .mixed,
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

    private var canSave: Bool {
        !session.isClearingCanvas
            && (captureScope == .fullScreen || captureRegion != nil)
    }

    private func propertiesPanelCenter(in containerSize: CGSize) -> CGPoint {
        guard let selection = session.selectionViewportBounds
            ?? retainedSelectionViewportBounds
        else {
            return CGPoint(
                x: containerSize.width - propertiesPanelEdgePadding
                    - propertiesPanelSize.width / 2,
                y: containerSize.height / 2
            )
        }

        let halfWidth = propertiesPanelSize.width / 2
        let halfHeight = propertiesPanelSize.height / 2
        let x = min(
            max(
                selection.midX,
                propertiesPanelEdgePadding + halfWidth
            ),
            containerSize.width - propertiesPanelEdgePadding - halfWidth
        )
        let topY = selection.minY
            - propertiesPanelSelectionSpacing
            - halfHeight
        let bottomY = selection.maxY
            + propertiesPanelSelectionSpacing
            + halfHeight
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

    private func save(region: CGRect?) {
        guard !isSaving else { return }
        isSaving = true
        isCaptureChromeHidden = true

        Task { @MainActor in
            await Task.yield()
            try? await Task.sleep(nanoseconds: 80_000_000)
            onSave(
                saveConfiguration.destination,
                saveConfiguration.format,
                saveConfiguration.imageQuality,
                region,
                { didSubmit in
                    isSaving = false
                    if didSubmit {
                        onClose()
                    } else {
                        isCaptureChromeHidden = false
                    }
                }
            )
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
#endif
