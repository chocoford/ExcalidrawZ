//
//  PencilTipsSheetView.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 2/21/25.
//

import SwiftUI

#if os(iOS)
struct PencilTipsSheetView: View {
    @Environment(\.dismiss) private var dismiss

    @Environment(ToolState.self) private var toolState

    @State private var selectedMode: ToolState.PencilInteractionMode = .fingerMove
    @State private var scrollPosition: ToolState.PencilInteractionMode?
    @State private var isBubbleStageReady = false

    private var selectedPage: PencilTipPage {
        pages.first { $0.mode == selectedMode } ?? pages[0]
    }

    private var selectedIndex: Int {
        pages.firstIndex { $0.mode == selectedMode } ?? 0
    }

    private var pages: [PencilTipPage] {
        [
            PencilTipPage(
                mode: .fingerSelect,
                title: String(localizable: .applePencilInterationModeOneFingerSelectTitle),
                detail:
"""
• Drag with one finger to select
• Use two fingers to move or zoom the canvas
""",
                bubbles: [
                    PencilTipBubble(
                        id: "select-pencil",
                        imageName: "drag&sketch",
                        size: 132,
                        offset: CGSize(width: -142, height: -32),
                        control: CGSize(width: -76, height: -116),
                        delay: 0
                    ),
                    PencilTipBubble(
                        id: "select-drag",
                        imageName: "drag2select",
                        size: 178,
                        offset: CGSize(width: 2, height: 16),
                        control: CGSize(width: -18, height: -56),
                        delay: 0.07
                    ),
                    PencilTipBubble(
                        id: "select-zoom",
                        imageName: "pinch2zoom",
                        size: 128,
                        offset: CGSize(width: 146, height: -22),
                        control: CGSize(width: 78, height: -110),
                        delay: 0.14
                    )
                ]
            ),
            PencilTipPage(
                mode: .fingerMove,
                title: String(localizable: .applePencilInterationModeOneFingerMoveTitle),
                detail:
"""
• Use one finger to move the canvas
• Use two fingers to move or zoom the canvas
• Select with the dedicated tool
""",
                bubbles: [
                    PencilTipBubble(
                        id: "move-pencil",
                        imageName: "drag&sketch",
                        size: 126,
                        offset: CGSize(width: -148, height: -18),
                        control: CGSize(width: -82, height: -100),
                        delay: 0
                    ),
                    PencilTipBubble(
                        id: "move-drag",
                        imageName: "drag2pan",
                        size: 184,
                        offset: CGSize(width: 0, height: 18),
                        control: CGSize(width: 18, height: -58),
                        delay: 0.07
                    ),
                    PencilTipBubble(
                        id: "move-zoom",
                        imageName: "pinch2zoom",
                        size: 132,
                        offset: CGSize(width: 150, height: -30),
                        control: CGSize(width: 78, height: -120),
                        delay: 0.14
                    )
                ]
            ),
            PencilTipPage(
                mode: .none,
                title: String(localizable: .applePencilInterationModeNoneTitle),
                detail: String(localizable: .applePencilInterationModeNoneTipsDescription),
                bubbles: [
                    PencilTipBubble(
                        id: "none-pencil",
                        imageName: "drag&sketch",
                        size: 128,
                        offset: CGSize(width: -148, height: -24),
                        control: CGSize(width: -82, height: -108),
                        delay: 0
                    ),
                    PencilTipBubble(
                        id: "none-drag",
                        imageName: "drag2draw",
                        size: 180,
                        offset: CGSize(width: 0, height: 18),
                        control: CGSize(width: -20, height: -58),
                        delay: 0.07
                    ),
                    PencilTipBubble(
                        id: "none-zoom",
                        imageName: "pinch2zoom",
                        size: 128,
                        offset: CGSize(width: 148, height: -22),
                        control: CGSize(width: 82, height: -112),
                        delay: 0.14
                    )
                ]
            )
        ]
    }

    var body: some View {
        VStack(spacing: 18) {
            Text(.localizable(.applePencilTipsTitle))
                .font(.title2.weight(.semibold))
                .multilineTextAlignment(.center)

            selectorContent()

            Text(.localizable(.applePencilTipsChangeInSettingsHelp))
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button {
                Task { @MainActor in
                    try? await toolState.setPencilInteractionMode(selectedMode)
                    dismiss()
                }
            } label: {
                Text(.localizable(.generalButtonSelect))
                    .frame(maxWidth: .infinity)
            }
            .modernButtonStyle(style: .glassProminent, size: .large, shape: .capsule)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 28)
        .frame(maxWidth: 560)
        .onAppear {
            selectMode(toolState.pencilInteractionMode, animated: false)
        }
        .task {
            isBubbleStageReady = false
            try? await Task.sleep(nanoseconds: 320_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                isBubbleStageReady = true
            }
        }
        .onChange(of: scrollPosition) { _, mode in
            guard let mode else { return }
            selectedMode = mode
        }
    }

    @ViewBuilder
    private func selectorContent() -> some View {
        VStack(spacing: 12) {
            previewImage()
            modePager()
            pageDots()
        }
    }

    @ViewBuilder
    private func previewImage() -> some View {
        GeometryReader { proxy in
            let scale = min(1, max(0.72, proxy.size.width / 500))
            ZStack {
                if isBubbleStageReady {
                    ForEach(selectedPage.bubbles) { bubble in
                        PencilTipBubbleView(bubble: bubble, scale: scale)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .id("\(selectedMode)-\(isBubbleStageReady)")
        }
        .frame(height: 254)
    }

    @ViewBuilder
    private func modePager() -> some View {
        GeometryReader { proxy in
            let cardWidth = max(240, proxy.size.width * 0.78)
            let sideInset = max(0, (proxy.size.width - cardWidth) / 2)

            ZStack {
                ScrollView(.horizontal) {
                    LazyHStack(spacing: 14) {
                        ForEach(pages) { page in
                            PencilTipPageView(
                                page: page,
                                isSelected: selectedMode == page.mode
                            )
                            .frame(width: cardWidth, height: 150)
                            .id(page.mode)
                            .scrollTransition(.interactive, axis: .horizontal) { content, phase in
                                content
                                    .scaleEffect(phase.isIdentity ? 1 : 0.88)
                                    .opacity(phase.isIdentity ? 1 : 0.52)
                                    .saturation(phase.isIdentity ? 1 : 0.72)
                            }
                        }
                    }
                    .scrollTargetLayout()
                    .padding(.vertical, 18)
                }
                .scrollIndicators(.hidden)
                .scrollClipDisabled()
                .scrollTargetBehavior(.viewAligned)
                .scrollPosition(id: $scrollPosition)
                .contentMargins(.horizontal, sideInset, for: .scrollContent)

                HStack {
                    sideNavigationButton(systemName: "chevron.left", offset: -1)
                        .disabled(selectedIndex == 0)
                    Spacer()
                    sideNavigationButton(systemName: "chevron.right", offset: 1)
                        .disabled(selectedIndex == pages.count - 1)
                }
                .padding(.horizontal, 2)
                .zIndex(2)
            }
        }
        .frame(height: 186)
    }

    @ViewBuilder
    private func pageDots() -> some View {
        HStack(spacing: 7) {
            ForEach(pages) { page in
                Circle()
                    .fill(selectedMode == page.mode ? Color.accentColor : .secondary.opacity(0.35))
                    .frame(width: selectedMode == page.mode ? 8 : 6, height: selectedMode == page.mode ? 8 : 6)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        selectMode(page.mode)
                    }
            }
        }
        .animation(.smooth, value: selectedMode)
    }

    @ViewBuilder
    private func sideNavigationButton(systemName: String, offset: Int) -> some View {
        Button {
            moveSelection(by: offset)
        } label: {
            Image(systemName: systemName)
                .font(.headline.weight(.semibold))
                .frame(width: 26, height: 26)
        }
        .modernButtonStyle(style: .glass, size: .large, shape: .circle)
        .shadow(color: .black.opacity(0.10), radius: 12, x: 0, y: 6)
    }

    private func moveSelection(by offset: Int) {
        let nextIndex = (selectedIndex + offset).clamped(to: 0...(pages.count - 1))
        selectMode(pages[nextIndex].mode)
    }

    private func selectMode(_ mode: ToolState.PencilInteractionMode, animated: Bool = true) {
        let update = {
            selectedMode = mode
            scrollPosition = mode
        }

        if animated {
            withAnimation(.smooth) {
                update()
            }
        } else {
            update()
        }
    }
}

private struct PencilTipPage: Identifiable {
    let mode: ToolState.PencilInteractionMode
    let title: String
    let detail: String
    let bubbles: [PencilTipBubble]

    var id: ToolState.PencilInteractionMode { mode }
}

private struct PencilTipBubble: Identifiable {
    let id: String
    let imageName: String
    let size: CGFloat
    let offset: CGSize
    let control: CGSize
    let delay: TimeInterval

    private var seed: Double {
        Double(id.unicodeScalars.reduce(0) { $0 + Int($1.value) })
    }

    var floatAmplitude: CGFloat {
        4 + CGFloat(seed.truncatingRemainder(dividingBy: 4))
    }

    var floatDuration: TimeInterval {
        2.4 + seed.truncatingRemainder(dividingBy: 5) * 0.18
    }

    var floatStart: CGFloat {
        seed.truncatingRemainder(dividingBy: 2) == 0 ? 1 : -1
    }

    var rotationAmplitude: Double {
        1.1 + seed.truncatingRemainder(dividingBy: 4) * 0.28
    }

    var horizontalFloatAmplitude: CGFloat {
        1.2 + CGFloat(seed.truncatingRemainder(dividingBy: 3)) * 0.45
    }
}

private struct PencilTipBubbleView: View {
    @Environment(\.colorScheme) private var colorScheme

    let bubble: PencilTipBubble
    let scale: CGFloat

    @State private var progress: CGFloat = 0
    @State private var floatingProgress: CGFloat = 0

    var body: some View {
        let visibleProgress = min(max(progress, 0), 1)
        let floatProgress = visibleProgress * visibleProgress
        let floatX = floatingProgress * bubble.horizontalFloatAmplitude * scale * floatProgress
        let floatY = floatingProgress * bubble.floatAmplitude * scale * floatProgress
        let rotation = Double(floatingProgress) * bubble.rotationAmplitude * Double(floatProgress)

        bubbleContent
            .frame(width: bubble.size * scale, height: bubble.size * scale)
            .clipShape(Circle())
            .contentShape(Circle())
            .compositingGroup()
            .shadow(
                color: .black.opacity(0.16 + 0.04 * visibleProgress),
                radius: (18 + 8 * visibleProgress) * scale,
                x: 0,
                y: (10 + 8 * visibleProgress) * scale
            )
            .scaleEffect(0.28 + progress * 0.76)
            .opacity(visibleProgress)
            .rotationEffect(.degrees(rotation))
            .modifier(
                CurvedBubbleMotionModifier(
                    progress: progress,
                    target: CGSize(
                        width: bubble.offset.width * scale,
                        height: bubble.offset.height * scale
                    ),
                    control: CGSize(
                        width: bubble.control.width * scale,
                        height: bubble.control.height * scale
                    )
                )
            )
            .offset(x: floatX, y: floatY)
            .onAppear {
                floatingProgress = bubble.floatStart
                withAnimation(
                    .spring(response: 0.72, dampingFraction: 0.58, blendDuration: 0.08)
                        .delay(bubble.delay)
                ) {
                    progress = 1
                }
                withAnimation(
                    .easeInOut(duration: bubble.floatDuration)
                        .delay(bubble.delay + 0.72)
                        .repeatForever(autoreverses: true)
                ) {
                    floatingProgress = -bubble.floatStart
                }
            }
            .onDisappear {
                progress = 0
                floatingProgress = bubble.floatStart
            }
    }

    @ViewBuilder
    private var bubbleContent: some View {
        ZStack {
            PencilTipGlassCircle()

            bubbleImage
                .clipShape(Circle())

            Circle()
                .strokeBorder(.white.opacity(0.54), lineWidth: 1.4)
                .blur(radius: 0.25)

            Circle()
                .fill(
                    LinearGradient(
                        colors: [
                            .white.opacity(0.42),
                            .white.opacity(0.08),
                            .clear
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .blendMode(.screen)

            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            .white.opacity(0.28),
                            .clear
                        ],
                        center: .topLeading,
                        startRadius: 0,
                        endRadius: bubble.size * scale * 0.72
                    )
                )
                .blendMode(.screen)
        }
    }

    @ViewBuilder
    private var bubbleImage: some View {
        let image = Image(bubble.imageName)
            .resizable()
            .scaledToFill()
            .padding(9 * scale)

        if colorScheme == .dark {
            image
                .colorInvert()
                .hueRotation(Angle(degrees: 180))
                .background(Color.black)
        } else {
            image
                .background(Color.white)
        }
    }
}

private struct PencilTipGlassCircle: View {
    var body: some View {
        ZStack {
            Circle()
                .fill(.white)

            Circle()
                .fill(.white.opacity(0.58))

            ZStack {
                if #available(iOS 26.0, *) {
                    Circle()
                        .fill(.clear)
                        .glassEffect(.regular, in: Circle())
                } else {
                    Circle()
                        .fill(.ultraThinMaterial)
                }
            }
            .opacity(0.82)

            Circle()
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        }
    }
}

private struct CurvedBubbleMotionModifier: AnimatableModifier {
    var progress: CGFloat
    let target: CGSize
    let control: CGSize

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func body(content: Content) -> some View {
        content.offset(currentOffset)
    }

    private var currentOffset: CGSize {
        let t = progress
        let inverse = 1 - t
        return CGSize(
            width: 2 * inverse * t * control.width + t * t * target.width,
            height: 2 * inverse * t * control.height + t * t * target.height
        )
    }
}

private struct PencilTipPageView: View {
    let page: PencilTipPage
    let isSelected: Bool

    private var tintStyle: AnyShapeStyle {
        isSelected
            ? AnyShapeStyle(Color.accentColor.opacity(0.13))
            : AnyShapeStyle(Color.clear)
    }

    private var borderStyle: AnyShapeStyle {
        isSelected
            ? AnyShapeStyle(Color.accentColor.opacity(0.45))
            : AnyShapeStyle(SeparatorShapeStyle())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(page.title)
                    .font(.headline)
                    .foregroundStyle(.primary)

                Spacer(minLength: 8)

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? .green : .secondary)
            }

            Text(page.detail)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background {
            ZStack {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(.regularMaterial)
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(tintStyle)
            }
            .shadow(
                color: .black.opacity(isSelected ? 0.14 : 0.08),
                radius: isSelected ? 20 : 14,
                x: 0,
                y: isSelected ? 12 : 8
            )
        }
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(borderStyle)
        }
        .padding(.horizontal, 2)
        .scaleEffect(isSelected ? 1 : 0.985)
        .animation(.smooth, value: isSelected)
    }
}

#Preview {
    Color.clear
        .sheet(isPresented: .constant(true)) {
            PencilTipsSheetView()
        }
        .environment(ToolState())
}
#endif
