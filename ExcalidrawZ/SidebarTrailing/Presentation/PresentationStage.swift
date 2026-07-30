//
//  PresentationStage.swift
//  ExcalidrawZ
//
//  Created by Codex on 2026/7/27.
//

import SwiftUI

struct PresentationStage: View {
    let slides: [ExcalidrawPresentationSlide]
    let selectedIndex: Int
    let outgoingSlideIndex: Int?
    let transition: ExcalidrawPresentationConfiguration.Transition
    let isForwardTransition: Bool
    let transitionProgress: CGFloat

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                if let outgoingSlideIndex {
                    slideContent(at: outgoingSlideIndex)
                        .opacity(opacity(for: .outgoing))
                        .scaleEffect(scale(for: .outgoing))
                        .offset(
                            x: offset(
                                for: .outgoing,
                                width: geometry.size.width
                            )
                        )
                        .zIndex(0)
                }

                slideContent(at: selectedIndex)
                    .opacity(opacity(for: .incoming))
                    .scaleEffect(scale(for: .incoming))
                    .offset(
                        x: offset(
                            for: .incoming,
                            width: geometry.size.width
                        )
                    )
                    .zIndex(1)
            }
            .frame(
                width: geometry.size.width,
                height: geometry.size.height,
                alignment: .center
            )
        }
    }

    @ViewBuilder
    private func slideContent(at index: Int) -> some View {
        if let image = slides[index].image {
            platformImage(image)
                .resizable()
                .scaledToFit()
                .padding(24)
        } else {
            ProgressView()
                .controlSize(.large)
                .tint(.white)
        }
    }

    private enum Layer {
        case incoming
        case outgoing
    }

    private func opacity(for layer: Layer) -> Double {
        guard outgoingSlideIndex != nil else { return 1 }

        switch transition {
            case .none:
                return 1
            case .fade, .slide, .zoom:
                switch layer {
                    case .incoming:
                        return Double(transitionProgress)
                    case .outgoing:
                        return Double(1 - transitionProgress)
                }
        }
    }

    private func scale(for layer: Layer) -> CGFloat {
        guard transition == .zoom,
              outgoingSlideIndex != nil else {
            return 1
        }

        let amount: CGFloat = 0.06
        switch (layer, isForwardTransition) {
            case (.incoming, true):
                return 1 - amount * (1 - transitionProgress)
            case (.outgoing, true):
                return 1 + amount * transitionProgress
            case (.incoming, false):
                return 1 + amount * (1 - transitionProgress)
            case (.outgoing, false):
                return 1 - amount * transitionProgress
        }
    }

    private func offset(
        for layer: Layer,
        width: CGFloat
    ) -> CGFloat {
        guard transition == .slide,
              outgoingSlideIndex != nil else {
            return 0
        }

        let direction: CGFloat = isForwardTransition ? 1 : -1
        switch layer {
            case .incoming:
                return direction * width * (1 - transitionProgress)
            case .outgoing:
                return -direction * width * transitionProgress
        }
    }

    @ViewBuilder
    private func platformImage(_ image: PlatformImage) -> Image {
#if os(macOS)
        Image(nsImage: image)
#else
        Image(uiImage: image)
#endif
    }
}
