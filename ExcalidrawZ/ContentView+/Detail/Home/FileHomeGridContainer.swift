//
//  FileHomeGridContainer.swift
//  ExcalidrawZ
//

import SwiftUI
import ChocofordUI
import SmoothGradient

enum FileHomeGridBackend: Equatable {
    case swiftUI
    case appKit

    /// Change this source value to switch all callers that use the default.
    static let defaultBackend: Self = .swiftUI
}

#if os(macOS)
enum FileHomeHoverAnimationPolicy {
    case whenNotScrolling
    case disabled

    /// Set to .disabled to remove hover animations from the whole file home.
    static let current: Self = .whenNotScrolling
}

private struct FileHomeScrollHoverAnimationModifier: ViewModifier {
    @Environment(\.fileHomeItemHoverEffectsEnabled) private var hoverEffectsEnabled
    @Environment(\.fileHomeItemHoverAnimationsEnabled) private var animationsEnabled
    @State private var isScrolling = false

    @ViewBuilder
    func body(content: Content) -> some View {
        if hoverEffectsEnabled, FileHomeHoverAnimationPolicy.current == .whenNotScrolling {
            if #available(macOS 15.0, *) {
                content
                    .environment(\.fileHomeItemHoverSuppressed, isScrolling)
                    .environment(
                        \.fileHomeItemHoverAnimationsEnabled,
                        animationsEnabled && !isScrolling
                    )
                    .onScrollPhaseChange { _, phase in
                        setScrolling(phase != .idle)
                    }
                    .onDisappear {
                        setScrolling(false)
                    }
            } else {
                // Older systems have no SwiftUI scroll-phase callback.
                content.environment(\.fileHomeItemHoverAnimationsEnabled, false)
            }
        } else {
            content.environment(\.fileHomeItemHoverAnimationsEnabled, false)
        }
    }

    private func setScrolling(_ value: Bool) {
        guard isScrolling != value else { return }
        // Suppress hover immediately on entry. On returning to idle, allow
        // the card under the pointer to restore its shadow with animation.
        var transaction = Transaction()
        transaction.disablesAnimations = value
        withTransaction(transaction) {
            isScrolling = value
        }
    }
}
#endif

/// Owns the whole scrolling surface, including its header and folder grid.
/// Native scrolling must not be nested inside a SwiftUI ScrollView.
/// Select an implementation in code with the backend parameter.
struct FileHomeGridContainer<Header: View, Background: View>: View {
    let files: [FileState.ActiveFile]
    let itemWidth: CGFloat
    let contentRevision: Int
    let showsPlaceholder: Bool
    let bottomPadding: CGFloat
    let animatesChanges: Bool
    let backend: FileHomeGridBackend
    let diagnosticStage: FileHomeGridDiagnosticStage
    let header: Header
    let background: Background

    init(
        files: [FileState.ActiveFile],
        itemWidth: CGFloat = 240,
        contentRevision: Int = 0,
        showsPlaceholder: Bool = false,
        bottomPadding: CGFloat = 30,
        animatesChanges: Bool = true,
        backend: FileHomeGridBackend = .defaultBackend,
        diagnosticStage: FileHomeGridDiagnosticStage = .current,
        @ViewBuilder header: () -> Header,
        @ViewBuilder background: () -> Background
    ) {
        self.files = files
        self.itemWidth = itemWidth
        self.contentRevision = contentRevision
        self.showsPlaceholder = showsPlaceholder
        self.bottomPadding = bottomPadding
        self.animatesChanges = animatesChanges
        self.backend = backend
        self.diagnosticStage = diagnosticStage
        self.header = header()
        self.background = background()
    }

    @ViewBuilder
    var body: some View {
#if os(macOS)
        container
            .modifier(FileHomeSheetPresentationModifier())
            .environment(
                \.fileHomeItemHoverEffectsEnabled,
                diagnosticStage != .fullCachedCoversNoHover
                    && diagnosticStage != .fullNoHover
            )
            .environment(
                \.fileHomeItemHoverAnimationsEnabled,
                diagnosticStage != .fullHoverNoAnimation
            )
#else
        container
#endif
    }

    @ViewBuilder
    private var container: some View {
#if os(macOS)
        if diagnosticStage != .full {
            swiftUIContainer
        } else {
            switch backend {
                case .swiftUI:
                    swiftUIContainer
                case .appKit:
                    if #available(macOS 13.0, *), !showsPlaceholder {
                        MacFileHomeGridContainer(
                            files: files,
                            itemWidth: itemWidth,
                            contentRevision: contentRevision,
                            bottomPadding: bottomPadding,
                            animatesChanges: animatesChanges,
                            header: header,
                            background: background
                        )
                        // The native backend does not emit SwiftUI scroll phases.
                        .environment(\.fileHomeItemHoverAnimationsEnabled, false)
                    } else {
                        swiftUIContainer
                    }
            }
        }
#else
        swiftUIContainer
#endif
    }

    private var swiftUIContainer: some View {
        FileHomeContainer {
            VStack(spacing: 30) {
                header
                FileHomeFilesGrid(
                    files: files,
                    itemWidth: itemWidth,
                    contentRevision: contentRevision,
                    animatesChanges: animatesChanges,
                    diagnosticStage: diagnosticStage
                )
                .padding(.horizontal, 30)
            }
        }
        .showPlaceholder(
            showsPlaceholder && (
                diagnosticStage == .cardInteraction
                || diagnosticStage == .fullCachedCovers
                || diagnosticStage == .fullCachedCoversNoHover
                || diagnosticStage == .fullNoHover
                || diagnosticStage == .fullHoverNoAnimation
                || diagnosticStage == .full
            ),
            itemWidth: itemWidth
        )
        .contentBottomPadding(bottomPadding)
        .contentBackground { background }
    }
}

struct FileHomeContainer: View {
    @EnvironmentObject private var fileState: FileState
    @EnvironmentObject private var fileHomeItemTransitionState: FileHomeItemTransitionState

    var content: AnyView

    init<Content: View>(
        @ViewBuilder content: () -> Content
    ) {
        self.content = AnyView(content())
    }

    @State private var placeholderContentHeight: CGFloat = 0
    @State private var activeFileScrollTask: Task<Void, Never>?

    private let activeFilePreparationDelay: Duration = .milliseconds(50)

    var config = Config()

    var body: some View {
        ScrollViewReader { proxy in
            scrollView
                .watch(value: fileState.currentActiveFile, initial: true) { _, activeFile in
                    prepareActiveFileForCloseTransition(activeFile, using: proxy)
                }
                .watch(
                    value: fileHomeItemTransitionState.canShowItemContainerView,
                    initial: true
                ) { _, isVisible in
                    guard !isVisible else { return }
                    prepareActiveFileForCloseTransition(
                        fileState.currentActiveFile,
                        using: proxy
                    )
                }
                .onDisappear {
                    activeFileScrollTask?.cancel()
                }
        }
    }

    private var scrollView: some View {
        GeometryReader { viewport in
            scrollView(viewportHeight: viewport.size.height)
        }
    }

    private func scrollView(viewportHeight: CGFloat) -> some View {
        ScrollView {
            VStack(spacing: 0) {
                if config.isPlaceholderPresented {
                    content
                        .readHeight($placeholderContentHeight)
                } else {
                    content
                }

                Color.clear
                    .frame(height: config.isPlaceholderPresented
                           ? max(0, viewportHeight - placeholderContentHeight)
                           : 0)
                    .overlay(alignment: .top) {
                        if config.isPlaceholderPresented {
                            LazyVGrid(
                                columns: [
                                    .init(
                                        .adaptive(
                                            minimum: config.itemWidth,
                                            maximum: config.itemWidth * 2 - 0.1
                                        ),
                                        spacing: 20
                                    )
                                ],
                                spacing: 20
                            ) {
                                ForEach(0..<30) { _ in
                                    FileHomeItemView.placeholder()
                                }
                            }
                            .padding(.horizontal, 30)
                        }
                    }
                    .mask {
                        if config.isPlaceholderPresented {
                            if #available(macOS 14.0, iOS 17.0, *) {
                                Rectangle()
                                    .fill(
                                        SmoothLinearGradient(
                                            from: Color.white,
                                            to: Color.white.opacity(0.0),
                                            startPoint: .top,
                                            endPoint: .bottom
                                        )
                                    )
                            } else {
                                Rectangle()
                                    .fill(
                                        LinearGradient(
                                            colors: [.white, .white.opacity(0.0)],
                                            startPoint: .top,
                                            endPoint: .bottom
                                        )
                                    )
                            }
                        } else {
                            Color.clear
                        }
                    }
                    .overlay {
                        if config.isPlaceholderPresented {
                            if #available(macOS 14.0, iOS 17.0, *) {
                                Text(localizable: .homeNoFilesPlaceholder)
                                    .foregroundStyle(.placeholder)
                            } else {
                                Text(localizable: .homeNoFilesPlaceholder)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
            }
            // Lazy grids refine their estimated height while scrolling. Don't
            // feed that height into parent state just to fill the empty space.
            .frame(minHeight: viewportHeight, alignment: .top)
            .padding(.bottom, config.bottomPadding)
            .background {
                config.contentBackground
            }
        }
#if os(macOS)
        .modifier(FileHomeScrollHoverAnimationModifier())
#endif
    }

    private func prepareActiveFileForCloseTransition(
        _ activeFile: FileState.ActiveFile?,
        using proxy: ScrollViewProxy
    ) {
        activeFileScrollTask?.cancel()
        guard let activeFile,
              !fileHomeItemTransitionState.canShowItemContainerView else {
            return
        }

        let targetID = activeFile.id
        activeFileScrollTask = Task { @MainActor in
            await Task.yield()
            try? await Task.sleep(for: activeFilePreparationDelay)
            guard !Task.isCancelled,
                  fileState.currentActiveFile?.id == targetID,
                  !fileHomeItemTransitionState.canShowItemContainerView else {
                return
            }

            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                // No anchor means SwiftUI performs only the scrolling needed
                // to reveal the item; already-visible cards stay in place.
                proxy.scrollTo(targetID)
            }
        }
    }

    struct Config {
        var contentBackground: AnyView?
        var isPlaceholderPresented: Bool = false
        var itemWidth: CGFloat = 240
        var bottomPadding: CGFloat = 30
    }

    @MainActor
    func contentBackground<Background: View>(
        @ViewBuilder background: () -> Background
    ) -> Self {
        var view = self
        view.config.contentBackground = AnyView(background())
        return view
    }

    @MainActor
    func contentBottomPadding(_ padding: CGFloat) -> Self {
        var view = self
        view.config.bottomPadding = padding
        return view
    }

    @MainActor
    func showPlaceholder(_ isPresented: Bool, itemWidth: CGFloat) -> Self {
        var view = self
        view.config.isPlaceholderPresented = isPresented
        view.config.itemWidth = itemWidth
        return view
    }

}
