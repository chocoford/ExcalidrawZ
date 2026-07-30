//
//  PresentationSlideList.swift
//  ExcalidrawZ
//
//  Created by Codex on 2026/7/27.
//

import SwiftUI
import UniformTypeIdentifiers

struct PresentationSlideList: View {
    let slides: [ExcalidrawPresentationSlide]
    @Binding var selectedSlideID: String?
    @Binding var draggingSlideID: String?
    let onMove: (_ sourceID: String, _ targetID: String) -> Void
    let onDrop: () -> Void
    let onTransitionChange: (
        _ slideID: String,
        _ transition: ExcalidrawPresentationConfiguration.Transition
    ) -> Void
    let onTransitionDurationChange: (
        _ slideID: String,
        _ duration: TimeInterval
    ) -> Void
    let onTransitionDurationCommit: () -> Void

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(Array(slides.enumerated()), id: \.element.id) { index, slide in
                    PresentationSlideGroup(
                        slide: slide,
                        number: index + 1,
                        isSelected: selectedSlideID == slide.id,
                        isDragging: draggingSlideID == slide.id,
                        onSelect: {
                            selectedSlideID = slide.id
                        },
                        onTransitionChange: {
                            onTransitionChange(slide.id, $0)
                        },
                        onTransitionDurationChange: {
                            onTransitionDurationChange(slide.id, $0)
                        },
                        onTransitionDurationCommit: {
                            onTransitionDurationCommit()
                        }
                    )
                    .contentShape(Rectangle())
                    .onDrag {
                        draggingSlideID = slide.id
                        return NSItemProvider(object: slide.id as NSString)
                    } preview: {
                        PresentationSlideRow(
                            slide: slide,
                            number: index + 1,
                            isSelected: true
                        )
                        .frame(width: 240)
                    }
                    .onDrop(
                        of: [.plainText],
                        delegate: PresentationSlideDropDelegate(
                            targetSlideID: slide.id,
                            draggingSlideID: $draggingSlideID,
                            onMove: onMove,
                            onDrop: onDrop
                        )
                    )
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
        }
    }
}

private struct PresentationSlideGroup: View {
    let slide: ExcalidrawPresentationSlide
    let number: Int
    let isSelected: Bool
    let isDragging: Bool
    let onSelect: () -> Void
    let onTransitionChange: (
        ExcalidrawPresentationConfiguration.Transition
    ) -> Void
    let onTransitionDurationChange: (TimeInterval) -> Void
    let onTransitionDurationCommit: () -> Void

    @State private var isHovered = false

    var body: some View {
        VStack(spacing: 0) {
            PresentationSlideTransitionControl(
                transition: slide.transition,
                duration: slide.transitionDuration,
                isAddControlVisible: showsHoverControl,
                onTransitionChange: onTransitionChange,
                onDurationChange: onTransitionDurationChange,
                onDurationCommit: onTransitionDurationCommit
            )

            PresentationSlideRow(
                slide: slide,
                number: number,
                isSelected: isSelected
            )
            .onTapGesture(perform: onSelect)
        }
        .opacity(isDragging ? 0.45 : 1)
        .onHover { isHovered in
            withAnimation(.smooth(duration: 0.2)) {
                self.isHovered = isHovered
            }
        }
    }

    private var showsHoverControl: Bool {
#if os(macOS)
        isHovered
#else
        true
#endif
    }
}

private struct PresentationSlideRow: View {
    let slide: ExcalidrawPresentationSlide
    let number: Int
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Color.secondary.opacity(0.08)
                .aspectRatio(16 / 10, contentMode: .fit)
                .overlay {
                    if let image = slide.image {
                        platformImage(image)
                            .resizable()
                            .scaledToFit()
                            .padding(4)
                    } else {
                        ProgressView()
                            .controlSize(.small)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

            HStack(spacing: 6) {
                Text("\(number)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 18, alignment: .leading)

                Text(slide.title)
                    .font(.callout)
                    .lineLimit(1)

                Spacer(minLength: 0)
            }
        }
        .padding(8)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.12) : Color.clear)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(
                    isSelected ? Color.accentColor : Color.secondary.opacity(0.18),
                    lineWidth: isSelected ? 2 : 1
                )
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

private struct PresentationSlideDropDelegate: DropDelegate {
    let targetSlideID: String
    @Binding var draggingSlideID: String?
    let onMove: (_ sourceID: String, _ targetID: String) -> Void
    let onDrop: () -> Void

    func dropEntered(info: DropInfo) {
        guard let draggingSlideID,
              draggingSlideID != targetSlideID else {
            return
        }
        withAnimation(.smooth) {
            onMove(draggingSlideID, targetSlideID)
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        onDrop()
        return true
    }
}
