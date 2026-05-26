//
//  AICameraDirector.swift
//  ExcalidrawZ
//
//  Created by Codex
//

import Foundation
import CoreGraphics

@MainActor
final class AICameraDirector: AICameraSessionEventSink {
    struct DebugSnapshot: CustomStringConvertible {
        let phase: String
        let sessionID: String?
        let revision: Int
        let lastMutationAt: Date?
        let focusRect: CGRect?
        let interruptionReason: String?

        var description: String {
            let mutationText = lastMutationAt?.formatted(date: .omitted, time: .standard) ?? "nil"
            let rectText = focusRect.map {
                "x=\($0.origin.x.rounded()), y=\($0.origin.y.rounded()), w=\($0.size.width.rounded()), h=\($0.size.height.rounded())"
            } ?? "nil"
            return [
                "phase=\(phase)",
                "session=\(sessionID ?? "nil")",
                "revision=\(revision)",
                "lastMutationAt=\(mutationText)",
                "focusRect=\(rectText)",
                "interruptionReason=\(interruptionReason ?? "nil")"
            ].joined(separator: "\n")
        }
    }

    enum Phase: String {
        case idle
        case active
        case settling
        case interrupted
    }

    enum FocusUpdateMode {
        case append
        case replace
    }

    weak var coordinator: ExcalidrawCanvasView.Coordinator? {
        didSet {
            oldValue?.aiCameraEventSink = nil
            coordinator?.aiCameraEventSink = self
        }
    }

    private let settleDelay: Duration = .milliseconds(900)
    private let defaultOptions = ExcalidrawCore.AICameraSessionOptions(
        zoomBehavior: .fitWhenNeeded,
        followRate: 6,
        viewportPadding: .uniform(60),
        minZoom: 0.1,
        maxZoom: 2,
        safeAreaRatio: 0.85,
        revision: nil
    )
    private let insertedContentOptions = ExcalidrawCore.AICameraSessionOptions(
        zoomBehavior: .fitWhenNeeded,
        followRate: 6,
        viewportPadding: .uniform(32),
        minZoom: 0.1,
        maxZoom: 2.5,
        safeAreaRatio: 0.95,
        revision: nil
    )

    private var phase: Phase = .idle
    private var sessionID: String?
    private var revision: Int = 0
    private var lastMutationAt: Date?
    private var focusRect: CGRect?
    private var interruptionReason: String?
    private var autoEndTask: Task<Void, Never>?

    func beginSession(options: ExcalidrawCore.AICameraSessionOptions? = nil) async throws {
        autoEndTask?.cancel()
        if sessionID != nil, phase != .interrupted {
            return
        }
        guard let coordinator else { return }
        let response = try await coordinator.beginAICameraSession(options: options ?? defaultOptions)
        sessionID = response.sessionId
        phase = response.state == .settling ? .settling : .active
        interruptionReason = nil
    }

    func endSession(mode: ExcalidrawCore.AICameraEndMode = .settle) async throws {
        autoEndTask?.cancel()
        autoEndTask = nil
        guard let coordinator, let sessionID else { return }
        phase = mode == .settle ? .settling : .idle
        try await coordinator.endAICameraSession(
            sessionId: sessionID,
            options: .init(mode: mode)
        )
    }

    func suspend() {
        interruptionReason = "host_override"
        phase = .interrupted
        autoEndTask?.cancel()
        autoEndTask = nil
        guard let coordinator, let sessionID else {
            reset()
            return
        }
        Task { @MainActor [weak self, weak coordinator] in
            guard let self, let coordinator else { return }
            try? await coordinator.interruptAICameraSession(
                sessionId: sessionID,
                options: .init(reason: "host_override")
            )
            self.reset()
        }
    }

    func stop() {
        suspend()
    }

    func debugSnapshot() -> DebugSnapshot {
        DebugSnapshot(
            phase: phase.rawValue,
            sessionID: sessionID,
            revision: revision,
            lastMutationAt: lastMutationAt,
            focusRect: focusRect,
            interruptionReason: interruptionReason
        )
    }

    func submitMutationBatch(
        elements: [ExcalidrawElement],
        changedElementIDs: [String],
        mode: FocusUpdateMode = .append
    ) async throws {
        let ids = Set(changedElementIDs)
        guard !ids.isEmpty else { return }

        let changedRects = elements
            .filter { ids.contains($0.id) && !$0.cameraIsDeleted }
            .map(\.cameraFocusRect)
        guard let batchRect = union(of: changedRects) else { return }

        switch mode {
            case .append:
                focusRect = focusRect?.union(batchRect) ?? batchRect
            case .replace:
                focusRect = batchRect
        }
        try await submitTarget(
            .box(
                .init(
                    minX: Double(focusRect?.minX ?? batchRect.minX),
                    minY: Double(focusRect?.minY ?? batchRect.minY),
                    maxX: Double(focusRect?.maxX ?? batchRect.maxX),
                    maxY: Double(focusRect?.maxY ?? batchRect.maxY)
                )
            ),
            focusRect: focusRect
        )
    }

    func submitElementIDs(
        _ elementIDs: [String],
        mode: FocusUpdateMode = .replace
    ) async throws {
        let ids = Array(Set(elementIDs)).filter { !$0.isEmpty }
        guard !ids.isEmpty else { return }
        if mode == .replace {
            focusRect = nil
        }
        try await submitTarget(
            .elements(.init(ids: ids)),
            focusRect: focusRect
        )
    }

    func submitBounds(
        _ bounds: CGRect,
        mode: FocusUpdateMode = .append,
        options: ExcalidrawCore.AICameraSessionOptions? = nil
    ) async throws {
        guard !bounds.isNull, !bounds.isEmpty else { return }

        switch mode {
            case .append:
                focusRect = focusRect?.union(bounds) ?? bounds
            case .replace:
                focusRect = bounds
        }

        try await submitTarget(
            .box(
                .init(
                    minX: Double(focusRect?.minX ?? bounds.minX),
                    minY: Double(focusRect?.minY ?? bounds.minY),
                    maxX: Double(focusRect?.maxX ?? bounds.maxX),
                    maxY: Double(focusRect?.maxY ?? bounds.maxY)
                )
            ),
            focusRect: focusRect,
            options: options
        )
    }

    func submitInsertedContentBounds(
        _ bounds: CGRect,
        mode: FocusUpdateMode = .append
    ) async throws {
        try await submitBounds(bounds, mode: mode, options: insertedContentOptions)
    }

    private func scheduleAutoEnd() {
        autoEndTask?.cancel()
        autoEndTask = Task { @MainActor [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: settleDelay)
            guard self.sessionID != nil, self.phase == .active else { return }
            try? await self.endSession(mode: .settle)
        }
    }

    private func reset() {
        autoEndTask?.cancel()
        autoEndTask = nil
        sessionID = nil
        revision = 0
        lastMutationAt = nil
        focusRect = nil
        if phase != .interrupted {
            interruptionReason = nil
        }
        if phase != .interrupted {
            phase = .idle
        }
    }

    private func union(of rects: [CGRect]) -> CGRect? {
        rects.reduce(into: nil as CGRect?) { partial, rect in
            partial = partial?.union(rect) ?? rect
        }
    }

    private func submitTarget(
        _ target: ExcalidrawCore.AICameraTarget,
        focusRect: CGRect?,
        options overrideOptions: ExcalidrawCore.AICameraSessionOptions? = nil
    ) async throws {
        lastMutationAt = Date()
        interruptionReason = nil

        try await beginSession(options: overrideOptions)
        guard let coordinator, let sessionID else { return }

        revision += 1
        var options = overrideOptions ?? defaultOptions
        options.revision = revision
        let response = try await coordinator.updateAICameraTarget(
            sessionId: sessionID,
            target: target,
            options: options
        )

        if response.accepted {
            self.focusRect = focusRect
            phase = response.state == .settling ? .settling : .active
            scheduleAutoEnd()
        } else if response.reason == "interrupted" {
            phase = .interrupted
            interruptionReason = response.reason
        }
    }

    func aiCameraSessionDidStart(_ info: ExcalidrawCore.AICameraSessionInfo) {
        sessionID = info.sessionId
        phase = .active
    }

    func aiCameraSessionDidUpdate(_ info: ExcalidrawCore.AICameraSessionInfo) {
        sessionID = info.sessionId ?? sessionID
        phase = info.state == .settling ? .settling : .active
        if let eventRevision = info.revision {
            revision = max(revision, eventRevision)
        }
    }

    func aiCameraSessionDidInterrupt(_ info: ExcalidrawCore.AICameraSessionInfo) {
        interruptionReason = info.reason
        phase = .interrupted
        sessionID = nil
        autoEndTask?.cancel()
        autoEndTask = nil
    }

    func aiCameraSessionDidSettle(_ info: ExcalidrawCore.AICameraSessionInfo) {
        sessionID = info.sessionId ?? sessionID
        phase = .settling
    }

    func aiCameraSessionDidEnd(_ info: ExcalidrawCore.AICameraSessionInfo) {
        if phase != .interrupted {
            phase = .idle
            interruptionReason = nil
        }
        sessionID = nil
        autoEndTask?.cancel()
        autoEndTask = nil
    }
}

private extension ExcalidrawElement {
    var cameraIsDeleted: Bool {
        switch self {
            case .generic(let element):
                element.isDeleted
            case .text(let element):
                element.isDeleted
            case .linear(let element):
                element.isDeleted
            case .arrow(let element):
                element.isDeleted
            case .freeDraw(let element):
                element.isDeleted
            case .draw(let element):
                element.isDeleted
            case .image(let element):
                element.isDeleted
            case .pdf(let element):
                element.isDeleted
            case .frameLike(let element):
                element.isDeleted
            case .iframeLike(let element):
                element.isDeleted
        }
    }

    var cameraFocusRect: CGRect {
        let minX = Swift.min(x, x + width)
        let minY = Swift.min(y, y + height)
        let rect = CGRect(
            x: minX,
            y: minY,
            width: abs(width),
            height: abs(height)
        )
        if rect.width == 0 || rect.height == 0 {
            return rect.insetBy(dx: -24, dy: -24)
        }
        return rect
    }
}
