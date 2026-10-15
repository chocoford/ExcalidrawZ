//
//  ViewerLocalRelay.swift
//  ExcalidrawZ
//
//  Relays opaque WebSocket messages between one editor and one local Viewer.
//  Scene reconciliation and message coalescing belong to the web runtime.
//

#if os(macOS)
import Foundation
import FlyingFox

actor ViewerLocalRelay {
    static let shared = ViewerLocalRelay()

    enum Role: String, Sendable {
        case editor
        case viewer

        var counterpart: Self { self == .editor ? .viewer : .editor }
    }

    private struct Peer {
        let id: UUID
        let output: AsyncStream<WSMessage>.Continuation
        let inputTask: Task<Void, Never>
    }

    private var rooms: [String: [Role: Peer]] = [:]

    func createSession() -> String {
        let id = UUID().uuidString
        rooms[id] = [:]
        return id
    }

    func containsSession(_ id: String) -> Bool {
        rooms[id] != nil
    }

    func endSession(_ id: String) {
        guard let peers = rooms.removeValue(forKey: id) else { return }
        for peer in peers.values {
            close(peer, code: .goingAway)
        }
    }

    func connect(
        sessionID: String,
        role: Role,
        input: AsyncStream<WSMessage>
    ) -> AsyncStream<WSMessage> {
        // Bound pending delivery. Losing an incremental scene message requires
        // reconnecting and requesting a full scene, rather than continuing.
        let (output, continuation) = AsyncStream<WSMessage>.makeStream(
            bufferingPolicy: .bufferingOldest(256)
        )
        guard rooms[sessionID] != nil else {
            continuation.yield(.close(.policyViolation))
            continuation.finish()
            return output
        }

        let peerID = UUID()
        if let previous = rooms[sessionID]?.removeValue(forKey: role) {
            close(previous, code: .goingAway)
        }

        let task = Task {
            for await message in input {
                guard !Task.isCancelled else { break }
                if case .close = message { break }
                forward(message, sessionID: sessionID, role: role, peerID: peerID)
            }
            disconnect(sessionID: sessionID, role: role, peerID: peerID)
        }
        rooms[sessionID]?[role] = Peer(id: peerID, output: continuation, inputTask: task)
        continuation.onTermination = { @Sendable [weak self] _ in
            Task {
                await self?.disconnect(sessionID: sessionID, role: role, peerID: peerID)
            }
        }
        return output
    }

    private func forward(_ message: WSMessage, sessionID: String, role: Role, peerID: UUID) {
        guard rooms[sessionID]?[role]?.id == peerID,
              let recipient = rooms[sessionID]?[role.counterpart] else { return }

        switch recipient.output.yield(message) {
            case .enqueued:
                break
            case .dropped:
                disconnect(sessionID: sessionID, role: role.counterpart, peerID: recipient.id,
                           code: .tryAgainLater)
            case .terminated:
                disconnect(sessionID: sessionID, role: role.counterpart, peerID: recipient.id)
            @unknown default:
                break
        }
    }

    private func disconnect(
        sessionID: String,
        role: Role,
        peerID: UUID,
        code: WSCloseCode = .normalClosure
    ) {
        // A replaced connection may terminate after its replacement is ready.
        guard rooms[sessionID]?[role]?.id == peerID,
              let peer = rooms[sessionID]?.removeValue(forKey: role) else { return }
        close(peer, code: code)
    }

    private func close(_ peer: Peer, code: WSCloseCode) {
        peer.inputTask.cancel()
        peer.output.yield(.close(code))
        peer.output.finish()
    }
}

struct ViewerLocalSocketHandler: WSMessageHandler {
    let sessionID: String
    let role: ViewerLocalRelay.Role

    func makeMessages(for client: AsyncStream<WSMessage>) async throws -> AsyncStream<WSMessage> {
        await ViewerLocalRelay.shared.connect(sessionID: sessionID, role: role, input: client)
    }
}

struct ViewerLocalRouteHandler: HTTPHandler {
    func handleRequest(_ request: HTTPRequest) async throws -> HTTPResponse {
        let components = request.path.split(separator: "/")
        guard components.count == 3,
              components[0] == "viewer",
              let role = ViewerLocalRelay.Role(rawValue: String(components[2])),
              await ViewerLocalRelay.shared.containsSession(String(components[1])) else {
            return HTTPResponse(statusCode: .notFound)
        }

        // Browser peers must originate from the bundled editor page.
        let expectedOrigin = "http://127.0.0.1:\(ExcalidrawServer.port)"
        guard request.headers[HTTPHeader("Origin")] == expectedOrigin else {
            return HTTPResponse(statusCode: .forbidden)
        }

        let handler = WebSocketHTTPHandler.webSocket(
            ViewerLocalSocketHandler(sessionID: String(components[1]), role: role)
        )
        return try await handler.handleRequest(request)
    }
}
#endif
