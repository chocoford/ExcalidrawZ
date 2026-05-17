//
//  AIChatRenderDebug.swift
//  ExcalidrawZ
//

import Foundation
import SwiftUI

#if DEBUG
final class AIChatRenderDebugState: ObservableObject {
    @Published var isEnabled = false
    @Published var hideMessageList = false
    @Published var useMinimalPromptInput = false
    @Published var hidePromptActionBar = false
    @Published var hideGeneratingEffect = false
    @Published var useStackMessageListHost = true

    func reset() {
        isEnabled = false
        hideMessageList = false
        useMinimalPromptInput = false
        hidePromptActionBar = false
        hideGeneratingEffect = false
        useStackMessageListHost = true
    }
}

enum AIChatRenderDebug {
    static let state = AIChatRenderDebugState()

    static var isEnabled: Bool {
        state.isEnabled
    }

    static var hideMessageList: Bool {
        state.hideMessageList
    }

    static var useMinimalPromptInput: Bool {
        state.useMinimalPromptInput
    }

    static var hidePromptActionBar: Bool {
        state.hidePromptActionBar
    }

    static var hideGeneratingEffect: Bool {
        state.hideGeneratingEffect
    }

    static var useStackMessageListHost: Bool {
        state.useStackMessageListHost
    }

    private static let counterStore = CounterStore()

    static func hit(_ name: String) {
        guard isEnabled else { return }
        counterStore.hit(name)
    }

    static func measure<T>(_ name: String, _ work: () -> T) -> T {
        guard isEnabled else { return work() }

        let start = CFAbsoluteTimeGetCurrent()
        let result = work()
        let elapsed = (CFAbsoluteTimeGetCurrent() - start) * 1000
        counterStore.hit(name, milliseconds: elapsed)
        return result
    }

    private final class CounterStore: @unchecked Sendable {
        struct TimingStats {
            var count: Int = 0
            var total: Double = 0
            var max: Double = 0

            mutating func record(_ milliseconds: Double) {
                count += 1
                total += milliseconds
                max = Swift.max(max, milliseconds)
            }
        }

        private let lock = NSLock()
        private var counts: [String: Int] = [:]
        private var timings: [String: TimingStats] = [:]
        private var lastFlush = CFAbsoluteTimeGetCurrent()

        func hit(_ name: String, milliseconds: Double? = nil) {
            lock.lock()
            if let milliseconds {
                timings[name, default: TimingStats()].record(milliseconds)
            } else {
                counts[name, default: 0] += 1
            }

            let now = CFAbsoluteTimeGetCurrent()
            guard now - lastFlush >= 1 else {
                lock.unlock()
                return
            }

            let countSnapshot = counts
                .sorted { lhs, rhs in
                    if lhs.value == rhs.value { return lhs.key < rhs.key }
                    return lhs.value > rhs.value
                }
                .prefix(20)
                .map { "\($0.key)=\($0.value)" }

            let timingSnapshot = timings
                .sorted { lhs, rhs in
                    if lhs.value.total == rhs.value.total { return lhs.key < rhs.key }
                    return lhs.value.total > rhs.value.total
                }
                .prefix(20)
                .map { name, stats in
                    let avg = stats.total / Double(max(stats.count, 1))
                    return String(
                        format: "%@ n=%d total=%.2fms avg=%.2fms max=%.2fms",
                        name,
                        stats.count,
                        stats.total,
                        avg,
                        stats.max
                    )
                }

            let snapshot = (countSnapshot + timingSnapshot)
                .joined(separator: " | ")

            counts.removeAll(keepingCapacity: true)
            timings.removeAll(keepingCapacity: true)
            lastFlush = now
            lock.unlock()

            if !snapshot.isEmpty {
                print("[AIChatRender] \(snapshot)")
            }
        }
    }
}
#else
enum AIChatRenderDebug {
    static func hit(_ name: String) {}

    static func measure<T>(_ name: String, _ work: () -> T) -> T {
        work()
    }

    static var hideMessageList: Bool { false }
    static var useMinimalPromptInput: Bool { false }
    static var hidePromptActionBar: Bool { false }
    static var hideGeneratingEffect: Bool { false }
    static var useStackMessageListHost: Bool { false }
}
#endif
