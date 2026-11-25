//
//  ExcalidrawZMCPServerController.swift
//  ExcalidrawZ
//
//  Created by Codex on 6/15/26.
//

import Observation
import Foundation
import Combine

enum ExcalidrawMCPServiceMode: String, CaseIterable, Identifiable {
    case basic
    case optimized

    var id: Self { self }
}

@MainActor
@Observable
final class ExcalidrawZMCPServerController {
    enum State: Equatable {
        case off
        case starting
        case running
        case stopping
        case failed(String)
    }

    static let shared = ExcalidrawZMCPServerController()
    nonisolated static var isAvailable: Bool {
#if os(macOS)
        true
#else
        false
#endif
    }

    private static let isEnabledDefaultsKey = "ExcalidrawZMCPServerEnabled"
    private static let serviceModeDefaultsKey = "ExcalidrawZMCPServiceMode"

    private(set) var state: State = .off
    private(set) var isEnabled: Bool
    private(set) var serviceMode: ExcalidrawMCPServiceMode

    let port: UInt16

    private var server: ExcalidrawZMCPServer?
    private var router: ExcalidrawMCPToolRouter?
    @ObservationIgnored private var serverTask: Task<Void, Never>?

    private init(port: UInt16 = ExcalidrawZMCPServer.defaultPort) {
        self.port = port
        guard Self.isAvailable else {
            self.isEnabled = false
            self.serviceMode = .basic
            return
        }

        self.isEnabled = UserDefaults.standard.bool(forKey: Self.isEnabledDefaultsKey)
        let loadedServiceMode = Self.loadServiceMode()
        let authorizedServiceMode = Self.authorizedServiceMode(loadedServiceMode)
        self.serviceMode = authorizedServiceMode

        if authorizedServiceMode != loadedServiceMode {
            Self.saveServiceMode(authorizedServiceMode)
        }

        if isEnabled {
            startServerIfNeeded()
        }
    }

    func setEnabled(_ enabled: Bool) {
        guard Self.isAvailable else {
            isEnabled = false
            state = .off
            return
        }

        guard isEnabled != enabled else { return }
        isEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: Self.isEnabledDefaultsKey)

        if enabled {
            startServerIfNeeded()
        } else {
            stopServerIfNeeded()
        }
    }

    func setServiceMode(_ mode: ExcalidrawMCPServiceMode) {
        guard Self.isAvailable else {
            serviceMode = .basic
            return
        }

        let authorizedMode = Self.authorizedServiceMode(mode)
        guard serviceMode != authorizedMode else {
            if authorizedMode != mode {
                Self.saveServiceMode(authorizedMode)
            }
            return
        }

        serviceMode = authorizedMode
        Self.saveServiceMode(authorizedMode)

        let router = router
        Task {
            await router?.setServiceMode(authorizedMode)
        }
    }

    func startServerIfNeeded() {
        guard Self.isAvailable else {
            state = .off
            return
        }

        guard serverTask == nil else { return }

        let router = ExcalidrawMCPToolRouter(serviceMode: serviceMode)
        let server = ExcalidrawZMCPServer(port: port, router: router)
        self.server = server
        self.router = router
        state = .starting

        serverTask = Task { [weak self, server, router] in
            do {
                let rawElementConverter = ExcalidrawMCPUpstreamRawElementConverter { elements in
                    try await ExcalidrawMCPAppBridge.shared.createElements(elements)
                }

                await router.setElementConverter { elements in
                    try await rawElementConverter.convertRawElements(elements)
                }
                await router.setSessionUpdateHandler { session in
                    try await ExcalidrawMCPAppBridge.shared.apply(session)
                }

                await MainActor.run {
                    self?.state = .running
                }

                try await server.start()

                await MainActor.run {
                    guard let self else { return }
                    self.finishServerTask(
                        unexpectedErrorMessage: "The MCP server stopped unexpectedly."
                    )
                }
            } catch is CancellationError {
                await MainActor.run {
                    guard let self else { return }
                    self.finishServerTask()
                }
            } catch {
                await MainActor.run {
                    guard let self else { return }
                    self.finishServerTask(unexpectedErrorMessage: error.localizedDescription)
                }
            }
        }
    }

    func stopServerIfNeeded() {
        guard let server else {
            state = .off
            return
        }

        state = .stopping
        Task { [server] in
            await server.stop()
        }
    }

    private func finishServerTask(unexpectedErrorMessage: String? = nil) {
        let wasStopping = state == .stopping
        let shouldRestart = isEnabled && wasStopping
        serverTask = nil
        server = nil
        router = nil

        if shouldRestart {
            startServerIfNeeded()
        } else if !isEnabled || wasStopping {
            state = .off
        } else if let unexpectedErrorMessage {
            state = .failed(unexpectedErrorMessage)
        } else {
            state = .off
        }
    }

    private static func loadServiceMode() -> ExcalidrawMCPServiceMode {
        guard let rawValue = UserDefaults.standard.string(forKey: serviceModeDefaultsKey),
              let mode = ExcalidrawMCPServiceMode(rawValue: rawValue) else {
            return .basic
        }
        return mode
    }

    private static func saveServiceMode(_ mode: ExcalidrawMCPServiceMode) {
        UserDefaults.standard.set(mode.rawValue, forKey: serviceModeDefaultsKey)
    }

    private static func authorizedServiceMode(_ mode: ExcalidrawMCPServiceMode) -> ExcalidrawMCPServiceMode {
        guard mode == .optimized,
              !Store.shared.canUseOptimizedMCPServices else {
            return mode
        }
        return .basic
    }
}
