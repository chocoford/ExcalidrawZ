//
//  ExcalidrawPresentationView.swift
//  ExcalidrawZ
//
//  Created by Codex on 2026/7/27.
//

import SwiftUI

struct ExcalidrawPresentationView: View {
    let session: ExcalidrawPresentationSession
    let onDismiss: () -> Void

    @State private var selectedIndex: Int
    @State private var outgoingSlideIndex: Int?
    @State private var isShowingControls = true
    @State private var isTransitioning = false
    @State private var activeTransition: ExcalidrawPresentationConfiguration.Transition = .none
    @State private var isForwardTransition = true
    @State private var transitionProgress: CGFloat = 1
    @State private var transitionCompletionTask: Task<Void, Never>?
#if os(macOS)
    @FocusState private var isFocused: Bool
#endif

    init(
        session: ExcalidrawPresentationSession,
        onDismiss: @escaping () -> Void
    ) {
        self.session = session
        self.onDismiss = onDismiss
        let initialIndex = session.slides.firstIndex {
            $0.id == session.initialSlideID
        } ?? 0
        _selectedIndex = State(initialValue: initialIndex)
    }

    private var slide: ExcalidrawPresentationSlide {
        session.slides[selectedIndex]
    }

    var body: some View {
        interactiveContent
    }

    @ViewBuilder
    private var interactiveContent: some View {
#if os(macOS)
        presentationContent
            .focusable()
            .focused($isFocused)
            .onMoveCommand { direction in
                switch direction {
                    case .left:
                        showPrevious()
                    case .right:
                        showNext()
                    default:
                        break
                }
            }
            .onExitCommand(perform: onDismiss)
            .onAppear {
                isFocused = true
            }
#else
        presentationContent
#endif
    }

    private var presentationContent: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()

            PresentationStage(
                slides: session.slides,
                selectedIndex: selectedIndex,
                outgoingSlideIndex: outgoingSlideIndex,
                transition: activeTransition,
                isForwardTransition: isForwardTransition,
                transitionProgress: transitionProgress
            )

            if isShowingControls {
                PresentationControls(
                    presentationTitle: session.title,
                    slideTitle: slide.title,
                    selectedIndex: selectedIndex,
                    slideCount: session.slides.count,
                    showPrevious: showPrevious,
                    showNext: showNext,
                    dismiss: onDismiss
                )
                .transition(.opacity)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.easeOut(duration: 0.2)) {
                isShowingControls.toggle()
            }
        }
        .gesture(
            DragGesture(minimumDistance: 40)
                .onEnded { value in
                    if value.translation.width < -40 {
                        showNext()
                    } else if value.translation.width > 40 {
                        showPrevious()
                    }
                }
        )
        .onDisappear {
            transitionCompletionTask?.cancel()
            transitionCompletionTask = nil
        }
    }

    private func showPrevious() {
        guard selectedIndex > 0 else { return }

        // A page's transition describes the boundary used to enter it.
        // Moving backward across that boundary reverses the current page's
        // enter transition.
        let sourceSlide = session.slides[selectedIndex]
        performTransition(
            to: selectedIndex - 1,
            transition: sourceSlide.transition,
            duration: sourceSlide.transitionDuration,
            isForward: false
        )
    }

    private func showNext() {
        guard selectedIndex < session.slides.count - 1 else {
            return
        }

        let targetSlide = session.slides[selectedIndex + 1]
        performTransition(
            to: selectedIndex + 1,
            transition: targetSlide.transition,
            duration: targetSlide.transitionDuration,
            isForward: true
        )
    }

    private func performTransition(
        to targetIndex: Int,
        transition: ExcalidrawPresentationConfiguration.Transition,
        duration: TimeInterval,
        isForward: Bool
    ) {
        completeActiveTransition()
        activeTransition = transition
        isForwardTransition = isForward

        guard transition != .none else {
            selectedIndex = targetIndex
            outgoingSlideIndex = nil
            transitionProgress = 1
            return
        }

        transitionCompletionTask?.cancel()
        outgoingSlideIndex = selectedIndex
        selectedIndex = targetIndex
        transitionProgress = 0
        isTransitioning = true

        transitionCompletionTask = Task { @MainActor in
            // Commit the two-layer initial state before animating its progress.
            // Otherwise SwiftUI can coalesce both mutations into one frame.
            try? await Task.sleep(for: .milliseconds(16))
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: duration)) {
                transitionProgress = 1
            }
            try? await Task.sleep(for: .seconds(duration))
            guard !Task.isCancelled else { return }
            outgoingSlideIndex = nil
            isTransitioning = false
            transitionCompletionTask = nil
        }
    }

    private func completeActiveTransition() {
        guard isTransitioning else { return }

        transitionCompletionTask?.cancel()
        transitionCompletionTask = nil

        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            transitionProgress = 1
            outgoingSlideIndex = nil
            isTransitioning = false
        }
    }
}
