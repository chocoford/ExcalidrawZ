//
//  CloudStorageConnectivityMonitor.swift
//  ExcalidrawZ
//

import Combine
import Foundation
import Network

@MainActor
final class CloudStorageConnectivityMonitor: ObservableObject {
    enum Status: Equatable, Sendable {
        case unknown
        case available
        case unavailable
    }

    static let shared = CloudStorageConnectivityMonitor()

    @Published private(set) var status: Status = .unknown

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "CloudStorageConnectivityMonitor")
    private var isStarted = false

    var canAttemptNetworkRequests: Bool {
        status != .unavailable
    }

    private init() {}

    func startIfNeeded() {
        guard !isStarted else { return }
        isStarted = true

        monitor.pathUpdateHandler = { path in
            let status: Status = path.status == .satisfied
                ? .available
                : .unavailable
            Task { @MainActor in
                CloudStorageConnectivityMonitor.shared.receive(status)
            }
        }
        monitor.start(queue: queue)
    }

    private func receive(_ status: Status) {
        guard self.status != status else { return }
        self.status = status
    }
}
