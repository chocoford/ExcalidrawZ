import Foundation
import LLMCore
import LLMKit
import XCTest
@testable import ExcalidrawZ

final class AIChatUsageTests: XCTestCase {
    func testReportedUsageSurvivesStorageAndDrivesHistoricalBilling() throws {
        try AIChatUsageFixture.validate()
    }
}

enum AIChatUsageFixture {
    static func validate() throws {
        let partial = LLMInferenceUsage(id: "first", generationID: "generation", billingSource: .byok,
            tokens: .init(promptTokens: 100, completionTokens: 10, totalTokens: 110))
        var final = partial
        final.tokens = .init(promptTokens: 100, completionTokens: 30, totalTokens: 130)
        final.isComplete = true
        final.providerToolUsage = ["web_search_requests": 2]
        let second = LLMInferenceUsage(id: "second", generationID: "generation", billingSource: .byok,
            tokens: .init(promptTokens: 50, completionTokens: 20, totalTokens: 70), isComplete: true,
            providerToolUsage: ["web_search_requests": 1])
        let title = LLMInferenceUsage(id: "title", generationID: "generation", billingSource: .byok, purpose: "title",
            tokens: .init(promptTokens: 500, completionTokens: 5, totalTokens: 505), isComplete: true)
        let old = LLMInferenceUsage(id: "replaced-request", generationID: "previous-generation", billingSource: .byok,
            tokens: .init(promptTokens: 900, completionTokens: 100, totalTokens: 1000), isComplete: true)
        let records = [final, second]
        let data = try AIInferenceUsageStorage.encode(records)
        try require(AIInferenceUsageStorage.decode(data) == records)
        try require(try AIInferenceUsageStorage.encode(nil) == nil)
        try require(AIInferenceUsageStorage.decode(nil) == nil)
        try require(AIInferenceUsageStorage.decode(Data("invalid".utf8)) == nil)
        let reply = ChatMessageContent(id: "reply", role: .assistant, content: "Answer", inferenceUsage: AIInferenceUsageStorage.decode(data))
        let conversation = Conversation(type: .regular, title: "Usage", messages: [
            .content(.init(role: .user, content: "Question", inferenceUsage: [title, old])),
            .content(.init(role: .assistant, toolCalls: [.init(id: "call", name: "draw", arguments: "{}")], inferenceUsage: [partial])),
            .content(.init(role: .tool, content: "Drawn", toolCallId: "call")), .content(reply)
        ], createdAt: .now, lastChatAt: .now)
        let turn = conversation.usageSummary(forMessageID: reply.id)
        try require(turn.requestCount == 2 && turn.isComplete)
        try require(turn.tokens == .init(promptTokens: 150, completionTokens: 50, totalTokens: 200))
        let byok = AIChatUsagePresentation(summary: turn, fallbackUsesBYOK: false)
        try require(byok.usesBYOK && byok.tokens?.totalTokens == 200 && !byok.isPartial)
        try require(byok.providerToolUsage?["web_search_requests"] == 3, "Search counters deduplicate model request snapshots")
        try require(!byok.showsCredits(0) && byok.showsCredits(2), "Platform service charges remain independent")

        let platform = LLMInferenceUsage(id: "platform", billingSource: .platform, tokens: final.tokens, isComplete: true)
        let historical = AIChatUsagePresentation(summary: .init([platform]), fallbackUsesBYOK: true)
        try require(!historical.usesBYOK && historical.tokens == nil && historical.showsCredits(0))
        let missing = LLMInferenceUsage(id: "missing", generationID: "generation", billingSource: .byok)
        let incomplete = AIChatUsagePresentation(summary: .init([final, missing]), fallbackUsesBYOK: false)
        try require(incomplete.tokens?.totalTokens == 130 && incomplete.isPartial)
        try require(incomplete.summary.unreportedRequestCount == 1 && incomplete.summary.incompleteRequestCount == 1)
        let unreported = AIChatUsagePresentation(summary: .init([missing]), fallbackUsesBYOK: false)
        try require(unreported.tokens == nil && !unreported.showsCredits(0))
        try require(unreported.providerToolUsage == nil && !unreported.hasProviderUsage)
        var metersOnly = missing
        metersOnly.providerToolUsage = ["web_search_requests": 0]
        let onlyTools = AIChatUsagePresentation(summary: .init([metersOnly]), fallbackUsesBYOK: false)
        try require(onlyTools.tokens == nil && onlyTools.hasProviderUsage && onlyTools.providerToolUsage?["web_search_requests"] == 0,
                    "A reported tool counter remains visible even without token statistics")
        let reportedZero = LLMInferenceUsage(billingSource: .byok,
            tokens: .init(promptTokens: 0, completionTokens: 0, totalTokens: 0), isComplete: true)
        let zero = AIChatUsagePresentation(summary: .init([reportedZero]), fallbackUsesBYOK: false)
        try require(zero.tokens?.totalTokens == 0 && !zero.isPartial)

        var updated = conversation
        var updatedReply = reply
        var updatedRecord = second
        updatedRecord.tokens?.totalTokens = 80
        updatedReply.inferenceUsage = [final, updatedRecord]
        updated.messages[updated.messages.count - 1] = .content(updatedReply)
        try require(AIChatUsagePresentation.signature(for: conversation) != AIChatUsagePresentation.signature(for: updated),
                    "A usage-only update must invalidate native row hosting")

        updatedRecord = second
        updatedRecord.providerToolUsage = ["web_search_requests": 4]
        updatedReply.inferenceUsage = [final, updatedRecord]
        updated.messages[updated.messages.count - 1] = .content(updatedReply)
        try require(AIChatUsagePresentation.signature(for: conversation) != AIChatUsagePresentation.signature(for: updated),
                    "Tool-meter-only updates must invalidate native row hosting")

        let source = LLMSourceCitation(url: URL(string: "https://sources.example/article")!, title: "Source")
        let updatedSource = LLMSourceCitation(url: source.url, title: "Updated source")
        let unsafe = LLMSourceCitation(url: URL(string: "file:///private/document")!)
        let sourcesData = try AISourceCitationStorage.encode([source, updatedSource, unsafe])
        try require(AISourceCitationStorage.decode(sourcesData) == [updatedSource])
        try require(try AISourceCitationStorage.encode(nil) == nil)
        try require(AISourceCitationStorage.decode(nil) == nil)
        try require(AISourceCitationStorage.decode(Data("invalid".utf8)) == nil)
        try require(try AISourceCitationStorage.decode(AISourceCitationStorage.encode([])) == [])
        updatedReply = reply
        updatedReply.citations = AISourceCitationStorage.decode(sourcesData)
        updated.messages[updated.messages.count - 1] = .content(updatedReply)
        try require(AIChatUsagePresentation.signature(for: conversation) != AIChatUsagePresentation.signature(for: updated),
                    "Source-only updates must invalidate native row hosting")
        let restoredReply = try JSONDecoder().decode(ChatMessageContent.self, from: JSONEncoder().encode(updatedReply))
        try require(restoredReply.citations == [updatedSource] && restoredReply.inferenceUsage == records)
    }

    private static func require(_ value: Bool, _ message: String = "Usage regression") throws {
        if !value { throw Failure.assertion(message) }
    }
    private enum Failure: Error { case assertion(String) }
}
