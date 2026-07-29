#if os(macOS)
import AppKit
import SwiftUI

struct ScreenCapturePermissionGuideView: View {
    let onClose: () -> Void

    var body: some View {
        HStack(spacing: 16) {
            DraggableApplicationIcon()
                .frame(width: 72, height: 72)

            DragDirectionArrow()
                .stroke(
                    Color.accentColor,
                    style: StrokeStyle(
                        lineWidth: 3,
                        lineCap: .round,
                        lineJoin: .round
                    )
                )
                .frame(width: 76, height: 48)
                .shadow(
                    color: Color.accentColor.opacity(0.25),
                    radius: 5
                )

            VStack(alignment: .leading, spacing: 6) {
                Text(localizable: .screenAnnotationPermissionGuideTitle)
                    .font(.headline.weight(.semibold))

                Text(localizable: .screenAnnotationPermissionGuideMessage)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            Button(action: onClose) {
                Image(systemName: "xmark")
            }
            .modernButtonStyle(
                style: .glass,
                size: .small,
                shape: .circle
            )
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity)
        .background {
            guideBackground
        }
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(
                    Color(nsColor: .separatorColor).opacity(0.6),
                    lineWidth: 0.5
                )
        }
    }

    @ViewBuilder
    private var guideBackground: some View {
        let shape = RoundedRectangle(
            cornerRadius: 20,
            style: .continuous
        )
        if #available(macOS 26.0, *) {
            shape
                .fill(.clear)
                .glassEffect(.regular, in: shape)
        } else {
            shape.fill(.regularMaterial)
        }
    }
}

private struct DragDirectionArrow: Shape {
    func path(in rect: CGRect) -> Path {
        let tip = CGPoint(x: rect.maxX - 4, y: rect.minY + 5)
        var path = Path()
        path.move(
            to: CGPoint(x: rect.minX + 3, y: rect.maxY - 5)
        )
        path.addCurve(
            to: tip,
            control1: CGPoint(
                x: rect.midX * 0.72,
                y: rect.maxY - 7
            ),
            control2: CGPoint(
                x: rect.midX * 1.18,
                y: rect.minY + 7
            )
        )
        path.move(
            to: CGPoint(x: tip.x - 18, y: tip.y + 1)
        )
        path.addLine(to: tip)
        path.addLine(
            to: CGPoint(x: tip.x - 3, y: tip.y + 18)
        )
        return path
    }
}

private struct DraggableApplicationIcon: NSViewRepresentable {
    func makeNSView(context: Context) -> DraggableApplicationIconView {
        DraggableApplicationIconView()
    }

    func updateNSView(
        _ nsView: DraggableApplicationIconView,
        context: Context
    ) {}
}

private final class DraggableApplicationIconView: NSImageView,
    NSDraggingSource
{
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        image = NSWorkspace.shared.icon(forFile: Bundle.main.bundlePath)
        imageScaling = .scaleProportionallyUpOrDown
        imageFrameStyle = .none
        isEditable = false
        unregisterDraggedTypes()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .openHand)
    }

    override func mouseDown(with event: NSEvent) {
        guard let image else { return }

        let applicationURL = Bundle.main.bundleURL as NSURL
        let item = NSDraggingItem(pasteboardWriter: applicationURL)
        item.setDraggingFrame(bounds, contents: image)
        beginDraggingSession(
            with: [item],
            event: event,
            source: self
        )
    }

    func draggingSession(
        _ session: NSDraggingSession,
        sourceOperationMaskFor context: NSDraggingContext
    ) -> NSDragOperation {
        .copy
    }

    func draggingSession(
        _ session: NSDraggingSession,
        endedAt screenPoint: NSPoint,
        operation: NSDragOperation
    ) {}
}
#endif
