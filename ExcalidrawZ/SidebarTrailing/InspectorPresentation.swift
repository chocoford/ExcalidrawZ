//
//  InspectorPresentation.swift
//  ExcalidrawZ
//
//  Created by Chocoford on 5/3/26.
//

import SwiftUI
import CoreData

import SFSafeSymbols
import ChocofordEssentials
import ChocofordUI
import UniformTypeIdentifiers

enum FloatingInspectorMetrics {
    static let widthStorageKey = "ExcalidrawFloatingInspectorWidth"
    static let defaultWidth: Double = 300
    static let minWidth: CGFloat = 260
    static let maxWidth: CGFloat = 440
#if os(iOS)
    static let horizontalPadding: CGFloat = 8
    static let controlsGap: CGFloat = 10
    static let controlsTopPadding: CGFloat = 6
#else
    static let horizontalPadding: CGFloat = 10
    static let controlsGap: CGFloat = 18
    static let controlsTopPadding: CGFloat = 16
#endif

    static func clampedWidth(_ width: CGFloat) -> CGFloat {
        min(max(width, minWidth), maxWidth)
    }

    static func controlsInset(for width: CGFloat) -> CGFloat {
        clampedWidth(width) + controlsGap
    }
}

struct InspectorPresentationModifier: ViewModifier {
    @Environment(\.containerHorizontalSizeClass) private var containerHorizontalSizeClass

    @EnvironmentObject private var appPreference: AppPreference
    @EnvironmentObject private var layoutState: LayoutState
    @EnvironmentObject private var fileState: FileState
    @EnvironmentObject private var lockedContentState: LockedContentStateStore

    @AppStorage(FloatingInspectorMetrics.widthStorageKey) private var floatingInspectorWidth = FloatingInspectorMetrics.defaultWidth
    @StateObject private var presentationModel = ExcalidrawPresentationModel()
    @State private var librariesToImport: [ExcalidrawLibrary] = []

    var shouldUseFloatingInspector: Bool {
        if appPreference.inspectorLayout == .floatingBar {
            return true
        } else if #available(iOS 26.0, *) {
            #if canImport(UIKit)
            if UIDevice.current.userInterfaceIdiom == .pad {
                /// inspector cause sidebar layout wierd in iPad
                return true
            } else {
                return false
            }
            #else
            return false
            #endif
        } else {
            return false
        }
    }

    private var shouldDisableInspectorContent: Bool {
        fileState.currentActiveFileIsInTrash &&
        layoutState.activeInspectorTab != .history
    }

    private var shouldShowInspectorPresentation: Bool {
        layoutState.isInspectorPresented &&
        !fileState.activeCollaborationFileIsLoading
    }

    private var isCompactIOS: Bool {
#if os(iOS)
        containerHorizontalSizeClass == .compact
#else
        false
#endif
    }

    private var usesCompactInspectorSheet: Bool {
#if os(iOS)
        isCompactIOS && !shouldUseFloatingInspector
#else
        false
#endif
    }

    private var floatingInspectorTopPadding: CGFloat {
#if os(iOS)
        58
#else
        10
#endif
    }

    private var floatingInspectorHorizontalPadding: CGFloat {
        FloatingInspectorMetrics.horizontalPadding
    }

    private var resolvedFloatingInspectorWidth: CGFloat {
        FloatingInspectorMetrics.clampedWidth(CGFloat(floatingInspectorWidth))
    }

    func body(content: Content) -> some View {
        ZStack {
            if shouldUseFloatingInspector {
                floatingInspector(content: content)
            } else if containerHorizontalSizeClass == .compact {
                content
                    .sheet(isPresented: $layoutState.isInspectorPresented) {
                        compactInspectorContent()
                    }
            } else if #available(macOS 14.0, iOS 17.0, *) {
                content
                    .inspector(isPresented: $layoutState.isInspectorPresented) {
                        inspectorContent()
                            .disabled(shouldDisableInspectorContent)
                            .inspectorColumnWidth(min: 280, ideal: 350, max: 400)
                    }
            } else {
                floatingInspector(content: content)
            }
        }
        // Island overlay lives on `ExcalidrawEditor` (not here) — the editor
        // is the actual frame the user perceives as "the canvas", and bottom-
        // center should be the canvas's bottom-center, not the whole window's.
        .modifier(ExcalidrawLibraryImporter(items: $librariesToImport))
#if os(iOS)
        .modifier(
            ExcalidrawPresentationCoverModifier(
                isEnabled: !usesCompactInspectorSheet
            )
        )
#endif
        .watch(value: lockedContentState.activeFileLockState) { lockState in
            guard lockState == .locked,
                  layoutState.isInspectorPresented else { return }

            layoutState.isInspectorPresented = false
        }
    }

    /// Picks the view shown inside the inspector based on the active tab.
    ///
    /// Intentionally *not* gated on `isInspectorPresented`. The native
    /// `.inspector(isPresented:)` modifier already handles the visual
    /// hide; gating here too would also tear down the active tab's
    /// view tree on every collapse, so reopening to the same tab pays
    /// the construction cost again. Letting the switch be the only
    /// condition means closing → reopening to the same tab is free,
    /// while switching to a different tab still rebuilds (which is
    /// what we want — different tabs have entirely different state).
    @ViewBuilder
    private func inspectorContent() -> some View {
        switch layoutState.activeInspectorTab {
            case .aiChat:
                AIChatView()
            case .library:
                LibraryView(librariesToImport: $librariesToImport)
            case .history:
                FileHistoryInspectorContent()
            case .presentation:
                PresentationInspectorContent(model: presentationModel)
            case .preference:
                CanvasSettingsInspectorContent()
            case .search:
                SearchInspectorContent()
#if DEBUG
            case .debug:
                DebugPanelView()
#endif
        }
    }

    @ViewBuilder
    private func compactInspectorContent() -> some View {
        if isCompactIOS {
            switch layoutState.activeInspectorTab {
                case .preference, .search, .presentation:
                    CompactInspectorNavigationSheet(
                        title: inspectorTitle,
                        usesLeadingCloseButton: layoutState.activeInspectorTab == .presentation,
                        onDismiss: {
                            layoutState.isInspectorPresented = false
                        }
                    ) {
                        inspectorContent()
                            .disabled(shouldDisableInspectorContent)
                    }
#if os(iOS)
                    // Present from the visible sheet. A cover attached to the
                    // editor behind it cannot take over until the sheet closes.
                    .modifier(ExcalidrawPresentationCoverModifier())
#endif
                default:
                    inspectorContent()
                        .disabled(shouldDisableInspectorContent)
            }
        } else {
            inspectorContent()
                .disabled(shouldDisableInspectorContent)
        }
    }

    private var inspectorTitle: String {
        switch layoutState.activeInspectorTab {
            case .aiChat:
                "AI Chat"
            case .library:
                String(localizable: .librariesTitle)
            case .history:
                String(localizable: .checkpoints)
            case .presentation:
                String(localizable: .presentationTitle)
            case .preference:
                String(localizable: .canvasPreferencesTitle)
            case .search:
                String(localizable: .searchButtonTitle)
#if DEBUG
            case .debug:
                "Debug"
#endif
        }
    }

    @ViewBuilder
    private func floatingInspector(content: Content) -> some View {
        ZStack {
            content
            HStack {
                Spacer()
                if shouldShowInspectorPresentation {
                    ZStack {
                        if isCompactIOS {
                            floatingInspectorPanelContent()
                                .frame(minWidth: 240, idealWidth: 250, maxWidth: 300)
                        } else {
                            floatingInspectorPanelContent()
                                .frame(width: resolvedFloatingInspectorWidth)
                                .overlay(alignment: .leading) {
                                    FloatingInspectorResizeHandle(width: $floatingInspectorWidth)
                                        .offset(x: -6)
                                }
                        }
                    }
                    .clipShape(
                        RoundedRectangle(
                            cornerRadius: floatingInspectorCornerRadius,
                            style: .continuous
                        )
                    )
                    .background {
                        if #available(iOS 26.0, macOS 26.0, *) {
                            RoundedRectangle(
                                cornerRadius: floatingInspectorCornerRadius,
                                style: .continuous
                            )
                                .fill(.background)
                                .glassEffect(
                                    .regular,
                                    in: RoundedRectangle(
                                        cornerRadius: floatingInspectorCornerRadius,
                                        style: .continuous
                                    )
                                )
#if os(macOS)
                                .shadow(radius: 4)
#endif
                        } else {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(.regularMaterial)
                                .shadow(radius: 4)
                        }
                    }
                    .transition(.move(edge: .trailing))
                }
            }
            .animation(.easeOut, value: shouldShowInspectorPresentation)
            .padding(.top, floatingInspectorTopPadding)
#if os(macOS)
            .padding(.bottom, 40)
#else
            .padding(.bottom, 10)
#endif
            .padding(.horizontal, floatingInspectorHorizontalPadding)
            .ignoresSafeArea(edges: .bottom)
        }
        .overlay(alignment: .topTrailing) {
#if os(macOS)
            if shouldShowInspectorPresentation {
                ExcalidrawTrailingControls()
                    .transition(.opacity)
            }
#endif
        }
        .animation(.easeOut, value: shouldShowInspectorPresentation)
    }

    private var floatingInspectorCornerRadius: CGFloat {
        if #available(iOS 26.0, macOS 26.0, *) {
            24
        } else {
            12
        }
    }

    @ViewBuilder
    private func floatingInspectorPanelContent() -> some View {
        if shouldUseFloatingNavigationInspectorContent {
            floatingNavigationInspectorContent()
        } else if floatingInspectorContentHasOwnTitle {
            inspectorContent()
                .disabled(shouldDisableInspectorContent)
        } else {
            VStack(spacing: 0) {
                floatingInspectorTitle()

                inspectorContent()
                    .disabled(shouldDisableInspectorContent)
            }
        }
    }

    private var shouldUseFloatingNavigationInspectorContent: Bool {
        switch layoutState.activeInspectorTab {
            case .aiChat, .library, .presentation:
                true
            case .history:
                !isCompactIOS
            default:
                false
        }
    }

    @ViewBuilder
    private func floatingNavigationInspectorContent() -> some View {
        NavigationStack {
            inspectorContent()
                .disabled(shouldDisableInspectorContent)
                .navigationTitle(inspectorTitle)
#if canImport(UIKit)
                .navigationBarTitleDisplayMode(.inline)
#endif
        }
    }

    private var floatingInspectorContentHasOwnTitle: Bool {
#if os(iOS)
        layoutState.activeInspectorTab == .history && isCompactIOS
#else
        false
#endif
    }

    @ViewBuilder
    private func floatingInspectorTitle() -> some View {
#if os(iOS)
        if #available(iOS 26.0, *),
           layoutState.activeInspectorTab == .aiChat {
            InspectorToolbarTitleLabel(title: inspectorTitle)
                .frame(maxWidth: .infinity)
                .padding(.top, 8)
                .padding(.bottom, 7)
                .padding(.horizontal, 10)
        } else {
            defaultFloatingInspectorTitle()
        }
#else
        defaultFloatingInspectorTitle()
#endif
    }

    @ViewBuilder
    private func defaultFloatingInspectorTitle() -> some View {
        Text(inspectorTitle)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .padding(.horizontal, 4)
    }
}

#if os(iOS)
private struct ExcalidrawPresentationCoverModifier: ViewModifier {
    @ObservedObject private var presentationController = ExcalidrawPresentationController.shared

    var isEnabled = true

    @ViewBuilder
    func body(content: Content) -> some View {
        if isEnabled {
            content
                .fullScreenCover(item: $presentationController.session) { session in
                    ExcalidrawPresentationView(
                        session: session,
                        onDismiss: presentationController.dismiss
                    )
                }
        } else {
            content
        }
    }
}
#endif

struct InspectorToolbarTitleLabel: View {
    let title: String

    var body: some View {
        Text(title)
            .foregroundStyle(.secondary)
            .font(.headline)
            .padding(.horizontal, 8)
    }
}

private struct FloatingInspectorResizeHandle: View {
    @Binding var width: Double

    @State private var dragStartWidth: CGFloat?
    @State private var isDragging = false

    var body: some View {
        ZStack {
            Color.clear
                .frame(width: 30)

            Capsule()
                .fill(Color.secondary.opacity(isDragging ? 0.42 : 0.22))
                .frame(width: 6, height: 34)
        }
        .contentShape(Rectangle())
        .hoverCursor(.columnResize(directions: .both))
        .gesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .global)
                .onChanged { value in
                    if dragStartWidth == nil {
                        dragStartWidth = CGFloat(width)
                    }
                    isDragging = true

                    let startWidth = dragStartWidth ?? CGFloat(width)
                    let proposedWidth = startWidth - value.translation.width
                    width = Double(FloatingInspectorMetrics.clampedWidth(proposedWidth))
                }
                .onEnded { _ in
                    dragStartWidth = nil
                    isDragging = false
                }
        )
    }
}

private struct CompactInspectorNavigationSheet<Content: View>: View {
    let title: String
    let usesLeadingCloseButton: Bool
    let onDismiss: () -> Void
    private let content: Content

    init(
        title: String,
        usesLeadingCloseButton: Bool = false,
        onDismiss: @escaping () -> Void,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.usesLeadingCloseButton = usesLeadingCloseButton
        self.onDismiss = onDismiss
        self.content = content()
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(title)
#if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
#endif
                .toolbar {
                    if usesLeadingCloseButton {
                        ToolbarItem(placement: .cancellationAction) {
                            Button(action: onDismiss) {
                                Label(.localizable(.generalButtonClose), systemSymbol: .xmark)
                                    .labelStyle(.iconOnly)
                            }
                            .accessibilityLabel(Text(localizable: .generalButtonClose))
                        }
                    } else {
                        ToolbarItem(placement: .confirmationAction) {
                            Button(action: onDismiss) {
                                Label(.localizable(.generalButtonDone), systemSymbol: .checkmark)
                                    .labelStyle(.iconOnly)
                            }
                            .accessibilityLabel(Text(localizable: .generalButtonDone))
                        }
                    }
                }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

/// Renders the title that appears at the top of the inspector chrome in sidebar mode.
/// The placement gymnastics are needed to push the toggle to the right and center the title across macOS versions.
struct InspectorHeaderToolbar: ToolbarContent {
    
    let title: String
    let isInspectorPresented: Bool
    
    var body: some ToolbarContent {
#if os(iOS)
        ToolbarItem(placement: .principal) {
            if isInspectorPresented {
                InspectorToolbarTitleLabel(title: title)
            }
        }
#else
        /// This is the key to make sidebar toggle at the right side.
        /// The `status` is work well in macOS 15.0+. But not well in macOS 14.0
        ToolbarItemGroup(placement:  .status) {
            if isInspectorPresented {
                if #available(macOS 15.0, iOS 18.0, *) {} else {
                    Spacer()
                }
                InspectorToolbarTitleLabel(title: title)
                if #available(macOS 15.0, iOS 18.0, *) {} else {
                    Spacer()
                }
            } else {
                if #available(macOS 26.0, *) {} else {
                    Color.clear
                        .frame(width: 1)
                }
            }
        }
#endif
        
    }
}
