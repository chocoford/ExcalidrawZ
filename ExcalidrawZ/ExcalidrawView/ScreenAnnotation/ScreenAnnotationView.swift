#if os(macOS)
import AppKit
import ChocofordUI
import SwiftUI

struct ScreenAnnotationView: View {
    @ObservedObject var session: ScreenAnnotationSession
    let onToggleFreeze: () -> Void
    let onClose: () -> Void

    private let tools: [ExcalidrawTool] = [
        .cursor,
        .arrow,
        .rectangle,
        .ellipse,
        .freedraw,
        .text,
        .eraser,
    ]

    var body: some View {
        ZStack {
            frozenBackground

            ScreenAnnotationWebView(session: session)
                .opacity(session.isReady ? 1 : 0)

            VStack(spacing: 0) {
                Spacer(minLength: 0)
                toolbar
                    .padding(.bottom, 48)
            }

            if !session.isReady {
                loadingIndicator
            }
        }
        .ignoresSafeArea()
        .animation(.easeOut(duration: 0.18), value: session.isReady)
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

    private var toolbar: some View {
        HStack(spacing: 8) {
            SegmentedPicker(selection: selectedToolBinding) {
                ForEach(tools, id: \.self) { tool in
                    SegmentedPickerItem(value: tool) {
                        ScreenAnnotationToolPickerItem(tool: tool)
                    }
                    .help(tool.help)
                }
            }

            Divider()
                .frame(height: 24)

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

            Divider()
                .frame(height: 24)

            Button(action: onToggleFreeze) {
                if session.isCapturingBackground {
                    ProgressView()
                } else {
                    let image = Image(
                        systemName: session.isFrozen ? "play.fill" : "pause.fill"
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

            Button(action: onClose) {
                Image(systemName: "xmark")
            }
            .help("Exit screen annotation")
            .modernButtonStyle(style: .glassProminent, size: .large, shape: .circle)
        }
        .padding(8)
        .background {
            toolbarBackground
        }
        .shadow(color: .black.opacity(0.16), radius: 18, y: 8)
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

    @ViewBuilder
    private var toolbarBackground: some View {
        if #available(macOS 26.0, *) {
            Capsule()
                .fill(.clear)
                .glassEffect(.regular, in: Capsule())
        } else {
            Capsule()
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

private struct ScreenAnnotationToolPickerItem: View {
    let tool: ExcalidrawTool

    private let size: CGFloat = 20

    private var labelType: LabelType {
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
            .padding(labelType == .svg ? 0 : size / 6)
            .aspectRatio(1, contentMode: .fit)
            .frame(width: size, height: size)
            .padding(size / 5)
            .padding(1)
    }

    private enum LabelType {
        case nativeShape
        case svg
        case image
    }
}
#endif
