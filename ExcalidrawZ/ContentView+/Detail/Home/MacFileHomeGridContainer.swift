//
//  MacFileHomeGridContainer.swift
//  ExcalidrawZ
//

#if os(macOS)
import SwiftUI
import AppKit

/// Match the existing adaptive grid's widths and spacing. Measuring a card is
/// needed only when these widths or the SwiftUI environment change.
struct FileHomeGridMetrics {
    let columns: Int
    let itemWidth: CGFloat

    init(viewportWidth: CGFloat, minimumItemWidth: CGFloat) {
        let availableWidth = max(1, viewportWidth - 60)
        let minimum = max(1, minimumItemWidth)
        columns = max(1, Int((availableWidth + 20) / (minimum + 20)))
        itemWidth = min(
            minimum * 2 - 0.1,
            max(1, (availableWidth - CGFloat(columns - 1) * 20) / CGFloat(columns))
        )
    }
}

@available(macOS 13.0, *)
struct MacFileHomeGridContainer<Header: View, Background: View>: View {
    @EnvironmentObject private var fileState: FileState
    @EnvironmentObject private var transitionState: FileHomeItemTransitionState

    let files: [FileState.ActiveFile]
    let itemWidth: CGFloat
    let contentRevision: Int
    let bottomPadding: CGFloat
    let animatesChanges: Bool
    let header: Header
    let background: Background

    var body: some View {
        MacFileHomeCollectionView(
            files: files,
            minimumItemWidth: itemWidth,
            contentRevision: contentRevision,
            bottomPadding: bottomPadding,
            animatesChanges: animatesChanges,
            fileToReveal: transitionState.canShowItemContainerView
                ? nil : fileState.currentActiveFile?.canonicalID,
            header: AnyView(header.background { background }),
            background: AnyView(background)
        )
    }
}

@available(macOS 13.0, *)
private struct MacFileHomeCollectionView: NSViewRepresentable {
    let files: [FileState.ActiveFile]
    let minimumItemWidth: CGFloat
    let contentRevision: Int
    let bottomPadding: CGFloat
    let animatesChanges: Bool
    let fileToReveal: String?
    let header: AnyView
    let background: AnyView

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> FileHomeNativeScrollView {
        let scrollView = FileHomeNativeScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.automaticallyAdjustsContentInsets = false

        let collectionView = FileHomeNativeCollectionView()
        collectionView.backgroundColors = [.clear]
        // The existing SwiftUI gestures own selection and drag behavior.
        collectionView.isSelectable = false
        collectionView.autoresizingMask = [.width]
        collectionView.collectionViewLayout = context.coordinator.layout
        collectionView.register(FileHomeNativeItem.self, forItemWithIdentifier: .fileHomeCard)
        collectionView.register(
            FileHomeNativeHeader.self,
            forSupplementaryViewOfKind: NSCollectionView.elementKindSectionHeader,
            withIdentifier: .fileHomeHeader
        )
        scrollView.documentView = collectionView
        context.coordinator.attach(collectionView, to: scrollView)
        scrollView.onViewportSizeChange = { [weak coordinator = context.coordinator] size in
            coordinator?.updateLayout(viewportSize: size)
        }
        context.coordinator.update(self, environment: context.environment)
        return scrollView
    }

    func updateNSView(_ nsView: FileHomeNativeScrollView, context: Context) {
        context.coordinator.update(self, environment: context.environment)
    }

    func sizeThatFits(
        _ proposal: ProposedViewSize,
        nsView: FileHomeNativeScrollView,
        context: Context
    ) -> CGSize? {
        // Answer SwiftUI's sizing probes without laying out a collection or
        // changing the currently visible native viewport during measurement.
        let width = proposal.width.flatMap { $0.isFinite ? $0 : nil } ?? nsView.frame.width
        let height = proposal.height.flatMap { $0.isFinite ? $0 : nil } ?? nsView.frame.height
        return CGSize(width: max(0, width), height: max(0, height))
    }

    static func dismantleNSView(_ nsView: FileHomeNativeScrollView, coordinator: Coordinator) {
        nsView.onViewportSizeChange = nil
        coordinator.revealTask?.cancel()
    }

    @MainActor
    final class Coordinator {
        let layout = FileHomeNativeFlowLayout()
        private weak var scrollView: NSScrollView?
        private weak var collectionView: NSCollectionView?
        private var dataSource: NSCollectionViewDiffableDataSource<Int, String>!
        private var files: [FileState.ActiveFile] = []
        private var filesByID: [String: FileState.ActiveFile] = [:]
        private var environment = EnvironmentValues()
        private var minimumItemWidth: CGFloat = 240
        private var viewportSize: CGSize = .zero
        private var measuredWidth: CGFloat?
        private var orderedIDs: [String] = []
        private var fileToReveal: String?
        private let headerController = NSHostingController(rootView: AnyView(EmptyView()))
        private let measurementController = NSHostingController(rootView: AnyView(EmptyView()))
        private let backgroundController = NSHostingController(rootView: AnyView(EmptyView()))
        var revealTask: Task<Void, Never>?

        func attach(_ collectionView: NSCollectionView, to scrollView: NSScrollView) {
            self.collectionView = collectionView
            self.scrollView = scrollView
            layout.minimumLineSpacing = 20
            layout.minimumInteritemSpacing = 20
            layout.sectionInset = NSEdgeInsets(top: 30, left: 30, bottom: 30, right: 30)
            layout.sectionHeadersPinToVisibleBounds = false
            headerController.sizingOptions = []
            measurementController.sizingOptions = []
            backgroundController.sizingOptions = []
            if #available(macOS 13.3, *) {
                headerController.safeAreaRegions = []
                measurementController.safeAreaRegions = []
                backgroundController.safeAreaRegions = []
            }
            collectionView.backgroundView = backgroundController.view

            dataSource = NSCollectionViewDiffableDataSource<Int, String>(
                collectionView: collectionView
            ) { [weak self] collectionView, indexPath, id in
                guard let self, let file = self.filesByID[id] else { return nil }
                let item = collectionView.makeItem(
                    withIdentifier: .fileHomeCard,
                    for: indexPath
                ) as! FileHomeNativeItem
                self.configure(item, file: file, id: id)
                return item
            }
            dataSource.supplementaryViewProvider = { [weak self] collectionView, kind, indexPath in
                guard let self else { return nil }
                let header = collectionView.makeSupplementaryView(
                    ofKind: kind,
                    withIdentifier: .fileHomeHeader,
                    for: indexPath
                ) as! FileHomeNativeHeader
                header.host(self.headerController.view)
                return header
            }
        }

        func update(_ container: MacFileHomeCollectionView, environment: EnvironmentValues) {
            self.environment = environment
            files = container.files
            filesByID.removeAll(keepingCapacity: true)
            var newIDs: [String] = []
            for file in files {
                let id = file.id
                if filesByID.updateValue(file, forKey: id) == nil { newIDs.append(id) }
            }
            minimumItemWidth = container.minimumItemWidth
            layout.sectionInset.bottom = container.bottomPadding
            headerController.rootView = AnyView(container.header.environment(\.self, environment))
            backgroundController.rootView = AnyView(container.background.environment(\.self, environment))

            // No snapshot application or rootView replacement happens in a
            // scroll callback. Environment objects remain live in each host.
            let identitiesChanged = orderedIDs != newIDs || dataSource.snapshot().sectionIdentifiers.isEmpty
            measuredWidth = nil
            updateLayout(viewportSize: scrollView?.contentView.bounds.size ?? .zero)

            if identitiesChanged {
                let shouldAnimate = container.animatesChanges && !orderedIDs.isEmpty
                orderedIDs = newIDs
                var snapshot = NSDiffableDataSourceSnapshot<Int, String>()
                snapshot.appendSections([0])
                snapshot.appendItems(newIDs)
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.22
                    dataSource.apply(snapshot, animatingDifferences: shouldAnimate)
                }
            }

            // Forward environment, metadata, and sibling ordering changes to
            // realized cards. Their .id preserves state unless cloud metadata
            // deliberately changes fileHomeItemContentID.
            for item in collectionView?.visibleItems() ?? [] {
                guard let item = item as? FileHomeNativeItem,
                      let id = item.fileID, let file = filesByID[id] else { continue }
                configure(item, file: file, id: id)
            }
            prepareFileForCloseTransition(container.fileToReveal, force: identitiesChanged)
        }

        private func card(for file: FileState.ActiveFile) -> AnyView {
            AnyView(
                FileHomeItemView(
                    file: file,
                    selectionSiblings: files,
                    interactionMode: .gridDiagnosticMode
                )
                    .id(file.fileHomeItemContentID)
                    .environment(\.self, environment)
                    .environment(\.fileHomeUsesNativeTransitionSource, true)
            )
        }

        private func configure(_ item: FileHomeNativeItem, file: FileState.ActiveFile, id: String) {
            item.fileID = id
            item.host(card(for: file))
        }

        func updateLayout(viewportSize: CGSize) {
            guard viewportSize.width > 0 else { return }
            let heightChanged = self.viewportSize.height != viewportSize.height
            self.viewportSize = viewportSize
            guard measuredWidth != viewportSize.width else {
                if heightChanged { layout.invalidateLayout() }
                return
            }
            measuredWidth = viewportSize.width
            if let collectionView, collectionView.frame.width != viewportSize.width {
                collectionView.setFrameSize(CGSize(width: viewportSize.width, height: collectionView.frame.height))
            }
            let metrics = FileHomeGridMetrics(
                viewportWidth: viewportSize.width,
                minimumItemWidth: minimumItemWidth
            )
            let headerSize = headerController.sizeThatFits(
                in: CGSize(width: viewportSize.width, height: .greatestFiniteMagnitude)
            )
            if let file = files.first {
                measurementController.rootView = card(for: file)
                let cardSize = measurementController.sizeThatFits(
                    in: CGSize(width: metrics.itemWidth, height: .greatestFiniteMagnitude)
                )
                layout.itemSize = CGSize(width: metrics.itemWidth, height: ceil(cardSize.height))
            }
            layout.headerReferenceSize = CGSize(width: viewportSize.width, height: ceil(headerSize.height))
            layout.invalidateLayout()
            prepareFileForCloseTransition(fileToReveal, force: true)
        }

        private func prepareFileForCloseTransition(_ fileID: String?, force: Bool = false) {
            guard force || fileToReveal != fileID else { return }
            fileToReveal = fileID
            revealTask?.cancel()
            guard let fileID else { return }
            revealTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(50))
                guard !Task.isCancelled, let self,
                      let id = self.filesByID.first(where: { $0.value.canonicalID == fileID })?.key,
                      let indexPath = self.dataSource.indexPath(for: id),
                      let collectionView = self.collectionView else { return }
                collectionView.layoutSubtreeIfNeeded()
                // AppKit names this edge after the horizontal edge itself;
                // it means the nearer of the top and bottom edges.
                collectionView.scrollToItems(
                    at: [indexPath],
                    scrollPosition: .nearestHorizontalEdge
                )
                collectionView.layoutSubtreeIfNeeded()
            }
        }
    }
}

private extension NSUserInterfaceItemIdentifier {
    static let fileHomeCard = NSUserInterfaceItemIdentifier("FileHomeCard")
    static let fileHomeHeader = NSUserInterfaceItemIdentifier("FileHomeHeader")
}

private final class FileHomeNativeScrollView: NSScrollView {
    var onViewportSizeChange: ((CGSize) -> Void)?
    private var lastViewportSize: CGSize = .zero

    override func layout() {
        super.layout()
        let size = contentView.bounds.size
        guard size != lastViewportSize else { return }
        lastViewportSize = size
        onViewportSizeChange?(size)
    }
}

private final class FileHomeNativeCollectionView: NSCollectionView {
    override var isFlipped: Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let hit = super.hitTest(point)
        // Give empty-space taps and folder drop targets to the original
        // SwiftUI background, without intercepting card gestures or menus.
        if hit === self, let backgroundView {
            // hitTest receives a point in the receiver's superview coordinates.
            return backgroundView.hitTest(convert(point, from: superview))
        }
        return hit
    }
}

private final class FileHomeNativeFlowLayout: NSCollectionViewFlowLayout {
    override var collectionViewContentSize: NSSize {
        var size = super.collectionViewContentSize
        size.height = max(size.height, collectionView?.enclosingScrollView?.contentView.bounds.height ?? 0)
        return size
    }

    override func shouldInvalidateLayout(forBoundsChange newBounds: NSRect) -> Bool {
        newBounds.width != collectionView?.bounds.width
    }
}

@available(macOS 13.0, *)
private final class FileHomeNativeItem: NSCollectionViewItem {
    var fileID: String?
    private var hostingController: NSHostingController<AnyView>?

    override func loadView() { view = FileHomeNativeHeader() }

    func host(_ rootView: AnyView) {
        if let hostingController {
            hostingController.rootView = rootView
        } else {
            let controller = NSHostingController(rootView: rootView)
            controller.sizingOptions = []
            if #available(macOS 13.3, *) { controller.safeAreaRegions = [] }
            hostingController = controller
            addChild(controller)
            (view as! FileHomeNativeHeader).host(controller.view)
        }
    }
}

/// An unclipped host preserves the existing card shadow and glass edges.
private final class FileHomeNativeHeader: NSView, NSCollectionViewElement {
    override var isFlipped: Bool { true }

    func host(_ hostedView: NSView) {
        guard hostedView.superview !== self else { return }
        clipsToBounds = false
        hostedView.removeFromSuperview()
        hostedView.frame = bounds
        hostedView.autoresizingMask = [.width, .height]
        hostedView.clipsToBounds = false
        addSubview(hostedView)
    }
}
#endif
