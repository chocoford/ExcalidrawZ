#if os(macOS)
import XCTest
import FlyingFox
@testable import ExcalidrawZ

final class ViewerLocalRelayTests: XCTestCase {
    func testMessagesStayWithinTheirSessionAndCanTravelBothWays() async {
        let relay = ViewerLocalRelay()
        let firstID = await relay.createSession()
        let secondID = await relay.createSession()
        let editor = AsyncStream<WSMessage>.makeStream()
        let viewer = AsyncStream<WSMessage>.makeStream()
        let otherViewer = AsyncStream<WSMessage>.makeStream()
        let editorOutput = await relay.connect(sessionID: firstID, role: .editor, input: editor.stream)
        let viewerOutput = await relay.connect(sessionID: firstID, role: .viewer, input: viewer.stream)
        let otherOutput = await relay.connect(sessionID: secondID, role: .viewer, input: otherViewer.stream)

        editor.continuation.yield(.text("scene"))
        let scene = await nextMessage(in: viewerOutput)
        XCTAssertEqual(scene, .text("scene"))
        viewer.continuation.yield(.data(Data([1, 2, 3])))
        let reply = await nextMessage(in: editorOutput)
        XCTAssertEqual(reply, .data(Data([1, 2, 3])))

        await relay.endSession(firstID)
        await relay.endSession(secondID)
        let otherMessage = await nextMessage(in: otherOutput)
        XCTAssertEqual(otherMessage, .close(.goingAway))
    }

    func testRevokedSessionsRejectLateConnections() async {
        let relay = ViewerLocalRelay()
        let id = await relay.createSession()
        await relay.endSession(id)
        let client = AsyncStream<WSMessage>.makeStream()
        let output = await relay.connect(sessionID: id, role: .viewer, input: client.stream)

        let message = await nextMessage(in: output)
        let exists = await relay.containsSession(id)
        XCTAssertEqual(message, .close(.policyViolation))
        XCTAssertFalse(exists)
    }

    func testOldConnectionTerminationDoesNotDisconnectItsReplacement() async {
        let relay = ViewerLocalRelay()
        let id = await relay.createSession()
        let editor = AsyncStream<WSMessage>.makeStream()
        let oldViewer = AsyncStream<WSMessage>.makeStream()
        let newViewer = AsyncStream<WSMessage>.makeStream()
        let editorOutput = await relay.connect(sessionID: id, role: .editor, input: editor.stream)
        let oldOutput = await relay.connect(sessionID: id, role: .viewer, input: oldViewer.stream)
        let newOutput = await relay.connect(sessionID: id, role: .viewer, input: newViewer.stream)

        oldViewer.continuation.finish()
        let close = await nextMessage(in: oldOutput)
        XCTAssertEqual(close, .close(.goingAway))
        editor.continuation.yield(.text("after reconnect"))
        let message = await nextMessage(in: newOutput)
        XCTAssertEqual(message, .text("after reconnect"))
        await relay.endSession(id)
        let editorClose = await nextMessage(in: editorOutput)
        XCTAssertEqual(editorClose, .close(.goingAway))
    }

    func testSlowViewerMustReconnectAfterItsDeliveryBufferOverflows() async {
        let relay = ViewerLocalRelay()
        let id = await relay.createSession()
        let editor = AsyncStream<WSMessage>.makeStream()
        let viewer = AsyncStream<WSMessage>.makeStream()
        let editorOutput = await relay.connect(sessionID: id, role: .editor, input: editor.stream)
        let viewerOutput = await relay.connect(sessionID: id, role: .viewer, input: viewer.stream)

        for index in 0..<300 { editor.continuation.yield(.text(String(index))) }
        editor.continuation.finish()
        // The editor closes only after all its input has been handled.
        _ = await nextMessage(in: editorOutput)
        let messages = await collectMessages(in: viewerOutput)
        XCTAssertEqual(messages.count, 256)

        let replacementEditor = AsyncStream<WSMessage>.makeStream()
        let replacementViewer = AsyncStream<WSMessage>.makeStream()
        let replacementOutput = await relay.connect(sessionID: id, role: .editor, input: replacementEditor.stream)
        let output = await relay.connect(sessionID: id, role: .viewer, input: replacementViewer.stream)
        replacementEditor.continuation.yield(.text("full resync"))
        let message = await nextMessage(in: output)
        XCTAssertEqual(message, .text("full resync"))
        await relay.endSession(id)
        let editorClose = await nextMessage(in: replacementOutput)
        XCTAssertEqual(editorClose, .close(.goingAway))
    }

    private func nextMessage(in stream: AsyncStream<WSMessage>) async -> WSMessage? {
        await withTaskGroup(of: WSMessage?.self) { group in
            group.addTask {
                var iterator = stream.makeAsyncIterator()
                return await iterator.next()
            }
            group.addTask {
                try? await Task.sleep(for: .seconds(2))
                return nil
            }
            let result = await group.next() ?? nil
            group.cancelAll()
            return result
        }
    }

    private func collectMessages(in stream: AsyncStream<WSMessage>) async -> [WSMessage] {
        await withTaskGroup(of: [WSMessage].self) { group in
            group.addTask {
                var result: [WSMessage] = []
                for await message in stream { result.append(message) }
                return result
            }
            group.addTask {
                try? await Task.sleep(for: .seconds(2))
                return []
            }
            let result = await group.next() ?? []
            group.cancelAll()
            return result
        }
    }
}
#endif
