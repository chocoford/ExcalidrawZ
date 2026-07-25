#if os(macOS)
import AppKit
import ChocofordUI
import SwiftUI

enum ScreenAnnotationCaptureScope: Hashable {
    case fullScreen
    case area
}

struct ScreenAnnotationCaptureRegionView: View {
    let containerSize: CGSize
    let onSelectionChange: (CGRect) -> Void

    @State private var selection: CGRect
    @State private var dragStartSelection: CGRect?

    private let minimumSize = CGSize(width: 120, height: 80)
    private let anchorSize: CGFloat = 14
    private let anchorHitSize: CGFloat = 32
    private let borderHitWidth: CGFloat = 24
    private let interactionCoordinateSpace = "ScreenAnnotationCaptureRegion"

    init(
        containerSize: CGSize,
        initialSelection: CGRect? = nil,
        onSelectionChange: @escaping (CGRect) -> Void
    ) {
        self.containerSize = containerSize
        self.onSelectionChange = onSelectionChange

        if let initialSelection {
            let width = min(
                max(initialSelection.width, minimumSize.width),
                containerSize.width
            )
            let height = min(
                max(initialSelection.height, minimumSize.height),
                containerSize.height
            )
            _selection = State(initialValue: CGRect(
                x: min(
                    max(initialSelection.minX, 0),
                    containerSize.width - width
                ),
                y: min(
                    max(initialSelection.minY, 0),
                    containerSize.height - height
                ),
                width: width,
                height: height
            ))
        } else {
            let width = max(320, containerSize.width * 0.56)
            let height = max(220, containerSize.height * 0.56)
            _selection = State(initialValue: CGRect(
                x: (containerSize.width - width) / 2,
                y: (containerSize.height - height) / 2,
                width: min(width, containerSize.width),
                height: min(height, containerSize.height)
            ))
        }
    }

    var body: some View {
        ZStack {
            captureMask

            selectionFrame
        }
        .frame(width: containerSize.width, height: containerSize.height)
        .coordinateSpace(name: interactionCoordinateSpace)
        .onAppear {
            onSelectionChange(selection.integral)
        }
    }

    private var captureMask: some View {
        Path { path in
            path.addRect(CGRect(origin: .zero, size: containerSize))
            path.addRect(selection)
        }
        .fill(
            Color.black.opacity(0.46),
            style: FillStyle(eoFill: true)
        )
        .allowsHitTesting(false)
    }

    private var selectionFrame: some View {
        ZStack {
            Rectangle()
                .stroke(
                    Color.white,
                    style: StrokeStyle(
                        lineWidth: 1.5,
                        dash: [7, 5]
                    )
                )
                .allowsHitTesting(false)

            selectionBorderHitArea
                .frame(
                    width: selection.width,
                    height: selection.height
                )

            ForEach(ResizeHandle.allCases) { handle in
                ZStack {
                    Circle()
                        .fill(.black.opacity(0.28))
                        .overlay {
                            Circle()
                                .stroke(Color.white, lineWidth: 2)
                        }
                        .frame(width: anchorSize, height: anchorSize)
                }
                    .frame(width: anchorHitSize, height: anchorHitSize)
                    .contentShape(Rectangle())
                    .position(handle.position(in: selection.size))
                    .gesture(resizeGesture(for: handle))
                    .modifier(
                        ScreenAnnotationPointerModifier(
                            style: handle.pointerStyle
                        )
                    )
            }
        }
        .frame(width: selection.width, height: selection.height)
        .position(x: selection.midX, y: selection.midY)
    }

    private var selectionBorderHitArea: some View {
        ZStack {
            horizontalBorderMoveHandle
                .position(x: selection.width / 2, y: 0)

            horizontalBorderMoveHandle
                .position(x: selection.width / 2, y: selection.height)

            verticalBorderMoveHandle
                .position(x: 0, y: selection.height / 2)

            verticalBorderMoveHandle
                .position(x: selection.width, y: selection.height / 2)
        }
    }

    private var horizontalBorderMoveHandle: some View {
        Color.clear
            .frame(height: borderHitWidth)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            .gesture(moveGesture)
            .modifier(
                ScreenAnnotationPointerModifier(
                    style: .move
                )
            )
    }

    private var verticalBorderMoveHandle: some View {
        Color.clear
            .frame(width: borderHitWidth)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(moveGesture)
            .modifier(
                ScreenAnnotationPointerModifier(
                    style: .move
                )
            )
    }

    private var moveGesture: some Gesture {
        DragGesture(
            minimumDistance: 1,
            coordinateSpace: .named(interactionCoordinateSpace)
        )
            .onChanged { value in
                if dragStartSelection == nil {
                    dragStartSelection = selection
                }
                guard let start = dragStartSelection else { return }
                let proposed = CGRect(
                    x: start.minX + value.translation.width,
                    y: start.minY + value.translation.height,
                    width: start.width,
                    height: start.height
                )
                selection = clamped(proposed)
            }
            .onEnded { _ in
                dragStartSelection = nil
                onSelectionChange(selection.integral)
            }
    }

    private func resizeGesture(for handle: ResizeHandle) -> some Gesture {
        DragGesture(
            minimumDistance: 0,
            coordinateSpace: .named(interactionCoordinateSpace)
        )
            .onChanged { value in
                if dragStartSelection == nil {
                    dragStartSelection = selection
                }
                guard let start = dragStartSelection else { return }
                selection = resized(
                    start,
                    handle: handle,
                    translation: value.translation
                )
            }
            .onEnded { _ in
                dragStartSelection = nil
                onSelectionChange(selection.integral)
            }
    }

    private func resized(
        _ rect: CGRect,
        handle: ResizeHandle,
        translation: CGSize
    ) -> CGRect {
        var minX = rect.minX
        var minY = rect.minY
        var maxX = rect.maxX
        var maxY = rect.maxY

        if handle.affectsLeft {
            minX = min(
                max(rect.minX + translation.width, 0),
                maxX - minimumSize.width
            )
        }
        if handle.affectsRight {
            maxX = max(
                min(rect.maxX + translation.width, containerSize.width),
                minX + minimumSize.width
            )
        }
        if handle.affectsTop {
            minY = min(
                max(rect.minY + translation.height, 0),
                maxY - minimumSize.height
            )
        }
        if handle.affectsBottom {
            maxY = max(
                min(rect.maxY + translation.height, containerSize.height),
                minY + minimumSize.height
            )
        }

        return CGRect(
            x: minX,
            y: minY,
            width: maxX - minX,
            height: maxY - minY
        )
    }

    private func clamped(_ rect: CGRect) -> CGRect {
        let width = min(max(rect.width, minimumSize.width), containerSize.width)
        let height = min(
            max(rect.height, minimumSize.height),
            containerSize.height
        )
        return CGRect(
            x: min(max(rect.minX, 0), containerSize.width - width),
            y: min(max(rect.minY, 0), containerSize.height - height),
            width: width,
            height: height
        )
    }

    private enum ResizeHandle: CaseIterable, Identifiable {
        case topLeft
        case top
        case topRight
        case right
        case bottomRight
        case bottom
        case bottomLeft
        case left

        var id: Self { self }

        var pointerStyle: ScreenAnnotationPointerStyle {
            switch self {
                case .topLeft:
                    .resize(.topLeading)
                case .top:
                    .resize(.top)
                case .topRight:
                    .resize(.topTrailing)
                case .right:
                    .resize(.trailing)
                case .bottomRight:
                    .resize(.bottomTrailing)
                case .bottom:
                    .resize(.bottom)
                case .bottomLeft:
                    .resize(.bottomLeading)
                case .left:
                    .resize(.leading)
            }
        }

        var affectsLeft: Bool {
            self == .topLeft || self == .left || self == .bottomLeft
        }

        var affectsRight: Bool {
            self == .topRight || self == .right || self == .bottomRight
        }

        var affectsTop: Bool {
            self == .topLeft || self == .top || self == .topRight
        }

        var affectsBottom: Bool {
            self == .bottomLeft || self == .bottom || self == .bottomRight
        }

        func position(in size: CGSize) -> CGPoint {
            switch self {
                case .topLeft:
                    CGPoint(x: 0, y: 0)
                case .top:
                    CGPoint(x: size.width / 2, y: 0)
                case .topRight:
                    CGPoint(x: size.width, y: 0)
                case .right:
                    CGPoint(x: size.width, y: size.height / 2)
                case .bottomRight:
                    CGPoint(x: size.width, y: size.height)
                case .bottom:
                    CGPoint(x: size.width / 2, y: size.height)
                case .bottomLeft:
                    CGPoint(x: 0, y: size.height)
                case .left:
                    CGPoint(x: 0, y: size.height / 2)
            }
        }
    }
}

private enum ScreenAnnotationPointerStyle {
    case move
    case resize(FrameResizePos)

    @MainActor
    var fallbackCursor: NSCursor {
        switch self {
            case .move:
                ScreenAnnotationCaptureRegionCursor.move
            case .resize(.top), .resize(.bottom):
                .resizeUpDown
            case .resize(.leading), .resize(.trailing):
                .resizeLeftRight
            case .resize(.topLeading), .resize(.bottomTrailing):
                ScreenAnnotationCaptureRegionCursor
                    .topLeftBottomRightResize
            case .resize(.topTrailing), .resize(.bottomLeading):
                ScreenAnnotationCaptureRegionCursor
                    .topRightBottomLeftResize
        }
    }
}

private struct ScreenAnnotationPointerModifier: ViewModifier {
    let style: ScreenAnnotationPointerStyle

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(macOS 15.0, *) {
            switch style {
                case .move:
                    content.pointerStyle(
                        .image(
                            Image(
                                systemName:
                                    "arrow.up.and.down.and.arrow.left.and.right"
                            ),
                            hotSpot: .center
                        )
                    )
                case .resize(let position):
                    content.pointerStyle(
                        .frameResize(
                            position: position.pointerPosition,
                            directions: .all
                        )
                    )
            }
        } else {
            content
                .onContinuousHover { phase in
                    switch phase {
                        case .active:
                            style.fallbackCursor.set()
                        case .ended:
                            NSCursor.arrow.set()
                    }
                }
                .onDisappear {
                    NSCursor.arrow.set()
                }
        }
    }
}

@available(macOS 15.0, *)
private extension FrameResizePos {
    var pointerPosition: FrameResizePosition {
        switch self {
            case .top:
                .top
            case .bottom:
                .bottom
            case .leading:
                .leading
            case .trailing:
                .trailing
            case .topLeading:
                .topLeading
            case .topTrailing:
                .topTrailing
            case .bottomLeading:
                .bottomLeading
            case .bottomTrailing:
                .bottomTrailing
        }
    }
}

@MainActor
private enum ScreenAnnotationCaptureRegionCursor {
    static let move: NSCursor = {
        guard let image = NSImage(
            systemSymbolName: "arrow.up.and.down.and.arrow.left.and.right",
            accessibilityDescription: nil
        ) else {
            return .openHand
        }
        return NSCursor(
            image: image,
            hotSpot: NSPoint(
                x: image.size.width / 2,
                y: image.size.height / 2
            )
        )
    }()

    static let topLeftBottomRightResize = makeCursor {
        let path = NSBezierPath()
        path.move(to: NSPoint(x: 4, y: 20))
        path.line(to: NSPoint(x: 20, y: 4))
        path.move(to: NSPoint(x: 4, y: 20))
        path.line(to: NSPoint(x: 10, y: 20))
        path.move(to: NSPoint(x: 4, y: 20))
        path.line(to: NSPoint(x: 4, y: 14))
        path.move(to: NSPoint(x: 20, y: 4))
        path.line(to: NSPoint(x: 14, y: 4))
        path.move(to: NSPoint(x: 20, y: 4))
        path.line(to: NSPoint(x: 20, y: 10))
        return path
    }

    static let topRightBottomLeftResize = makeCursor {
        let path = NSBezierPath()
        path.move(to: NSPoint(x: 4, y: 4))
        path.line(to: NSPoint(x: 20, y: 20))
        path.move(to: NSPoint(x: 4, y: 4))
        path.line(to: NSPoint(x: 10, y: 4))
        path.move(to: NSPoint(x: 4, y: 4))
        path.line(to: NSPoint(x: 4, y: 10))
        path.move(to: NSPoint(x: 20, y: 20))
        path.line(to: NSPoint(x: 14, y: 20))
        path.move(to: NSPoint(x: 20, y: 20))
        path.line(to: NSPoint(x: 20, y: 14))
        return path
    }

    private static func makeCursor(
        path makePath: () -> NSBezierPath
    ) -> NSCursor {
        let size = NSSize(width: 24, height: 24)
        let image = NSImage(size: size)
        image.lockFocus()
        defer { image.unlockFocus() }

        let path = makePath()
        path.lineCapStyle = .round
        path.lineJoinStyle = .round

        NSColor.white.setStroke()
        path.lineWidth = 4
        path.stroke()

        NSColor.black.setStroke()
        path.lineWidth = 2
        path.stroke()

        return NSCursor(
            image: image,
            hotSpot: NSPoint(x: size.width / 2, y: size.height / 2)
        )
    }
}
#endif
