//
//  RoundRevealOrchestrator.swift
//  ExcalidrawZ
//
//  Drives the sequential reveal of visual elements within an
//  `AssistantRoundView`: content first, tool calls second, tool results
//  third — each with a minimum dwell time AND a data-stability gate
//  before advancing to the next.
//
//  Why both a time gate and a data gate:
//  - Time gate (dwell) gives the eye a beat between elements so a burst
//    of data doesn't dump the whole round at once. Default dwells
//    target ~comfortable reading pace, not raw layout time.
//  - Data gate (isReady) prevents revealing the next element while the
//    previous one is still streaming. Specifically: a `content`
//    element is "unready" while it's the in-flight assistant message
//    AND no tool calls have arrived yet (content is still growing,
//    SmoothStreamingText is actively masking). Once tool calls land
//    (model committed to tool use, content sealed) or the message is
//    no longer in-flight, content becomes ready and the next element
//    can reveal.
//
//  Without the data gate, a fast turnaround (content arriving + tool
//  calls in the same chunk after the dwell expired) would reveal both
//  elements stacked in time, defeating the "ordered" intent. Without
//  the time gate, instant data arrivals would feel jolty.
//
//  Mode switching:
//  - paced: live rounds use the queue + dwell + readiness pipeline.
//  - snap: committed/historical rounds reveal everything at once on
//    mount — no point pacing data the user already had.
//
//  The orchestrator is owned per-`AssistantRoundView` instance (as a
//  `@StateObject`) so identity is preserved across body re-evals but
//  reset cleanly when the view unmounts.
//

import Foundation

@MainActor
final class RoundRevealOrchestrator: ObservableObject {
    /// Discriminator for what the visual element represents. Drives the
    /// dwell duration and the readiness defaults.
    enum Kind: Sendable, Hashable {
        case content
        case toolCall
        case toolResult
    }

    /// Stable, position-independent description of a visual element. The
    /// `id` must be deterministic for the same logical element across
    /// re-evals (we use `"content:<msgID>"` / `"toolcall:<msgID>:<callID>"`
    /// / `"toolresult:<msgID>"`).
    struct Element: Equatable, Identifiable, Sendable {
        let id: String
        let kind: Kind
        /// Can the orchestrator advance past this element? Set to `false`
        /// while this element's data is still being delivered (e.g.
        /// `content` of an in-flight message with no tool calls yet).
        /// Atomic kinds (`toolCall` / `toolResult`) should always be
        /// `true` — they're either present or not.
        let isReady: Bool
    }

    /// Element ids currently considered visible to the user. The view
    /// gates each rendered element on membership in this set.
    @Published private(set) var revealedIDs: Set<String> = []

    private var elements: [Element] = []
    private var index: Int = 0
    private var task: Task<Void, Never>?

    private static let readinessPollInterval: Duration = .milliseconds(150)

    /// Time gate **before** the data-readiness check. Floor for how long
    /// each element must be visible at minimum, regardless of whether
    /// its data has stabilized.
    static func dwell(for kind: Kind) -> Duration {
        switch kind {
            case .content:    return .milliseconds(800)
            case .toolCall:   return .milliseconds(350)
            case .toolResult: return .milliseconds(350)
        }
    }

    /// Settle time **after** `isReady` flips true. Lets the user absorb
    /// the just-stabilized element before the orchestrator advances
    /// and reveals the next one. Critical for `content` elements:
    /// without it, tool-call cards appeared the instant the content
    /// stream finished — no beat for the eye to land on the text.
    /// Atomic kinds use zero (they were already settled when revealed).
    static func postReadySettle(for kind: Kind) -> Duration {
        switch kind {
            case .content:    return .milliseconds(1500)
            case .toolCall:   return .zero
            case .toolResult: return .zero
        }
    }

    /// Live-mode update. New elements get appended to the reveal queue;
    /// readiness flags on existing elements may unblock a waiting task.
    /// Reordering or shrinking the elements array isn't supported here —
    /// callers should use `reset()` first if the round structure changed.
    ///
    /// Synchronously reveals the current-index element so the view's
    /// next render shows it without waiting for the Task scheduler.
    /// Without this, the very first element of a freshly-mounted live
    /// round is invisible for one runloop tick (Task hasn't ticked yet
    /// to do its insert), and on busy stream paths that gap can compound
    /// with body re-evals into "stuck invisible until something else
    /// invalidates the view." Set.insert is idempotent, so the Task's
    /// own insert later is a harmless no-op.
    func update(_ newElements: [Element]) {
        elements = newElements
        if index < elements.count {
            revealedIDs.insert(elements[index].id)
        }
        scheduleAdvance()
    }

    /// Snap-reveal everything immediately. Used for committed/historical
    /// rounds where pacing has nothing to add — the data is already
    /// settled, the user just wants to see it.
    func revealAllImmediately(_ newElements: [Element]) {
        task?.cancel()
        task = nil
        elements = newElements
        revealedIDs = Set(newElements.map(\.id))
        index = newElements.count
    }

    func reset() {
        task?.cancel()
        task = nil
        elements = []
        revealedIDs = []
        index = 0
    }

    private func scheduleAdvance() {
        guard task == nil else { return }
        guard index < elements.count else { return }

        task = Task { @MainActor [weak self] in
            guard let self else { return }
            while !Task.isCancelled, self.index < self.elements.count {
                let current = self.elements[self.index]

                // 1. Reveal current element if not already.
                self.revealedIDs.insert(current.id)

                // 2. Time gate: minimum dwell after reveal.
                try? await Task.sleep(for: Self.dwell(for: current.kind))

                // 3. Data gate: spin until *current* element (re-read on
                //    each tick, since upstream `update` calls can mutate
                //    its readiness flag) becomes ready. For atomic
                //    elements `isReady` is already true and we exit
                //    immediately; for `content` we wait for tool calls
                //    to land or the message to commit.
                while !Task.isCancelled,
                      self.index < self.elements.count,
                      !self.elements[self.index].isReady {
                    try? await Task.sleep(for: Self.readinessPollInterval)
                }

                // 4. Post-ready settle: extra beat AFTER readiness
                //    flips, so the next element doesn't pop in the
                //    instant streaming finishes. Without this, tool-call
                //    cards appeared the moment SmoothStreamingText
                //    locked content — no breathing room for the eye.
                try? await Task.sleep(for: Self.postReadySettle(for: current.kind))

                // 5. Advance.
                self.index += 1
            }
            self.task = nil
        }
    }
}
