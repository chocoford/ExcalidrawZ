import Foundation
import LLMCore

/// Persist the SDK's request records verbatim; totals are derived by LLMUsageSummary.
enum AIInferenceUsageStorage {
    static func encode(_ records: [LLMInferenceUsage]?) throws -> Data? {
        try records.map { try JSONEncoder().encode($0) }
    }

    static func decode(_ data: Data?) -> [LLMInferenceUsage]? {
        guard let data else { return nil }
        return try? JSONDecoder().decode([LLMInferenceUsage].self, from: data)
    }
}

/// Sources are optional provider metadata, never an instruction to fetch a URL.
enum AISourceCitationStorage {
    static func normalized(_ citations: [LLMSourceCitation]) -> [LLMSourceCitation] {
        var content = ChatMessageContent(role: .assistant)
        content.mergeCitations(citations)
        return content.citations ?? []
    }

    static func encode(_ citations: [LLMSourceCitation]?) throws -> Data? {
        try citations.map { try JSONEncoder().encode(normalized($0)) }
    }

    static func decode(_ data: Data?) -> [LLMSourceCitation]? {
        guard let data, let citations = try? JSONDecoder().decode([LLMSourceCitation].self, from: data) else { return nil }
        return normalized(citations)
    }

    static func signature(_ citations: [LLMSourceCitation]?) -> Int {
        var hasher = Hasher()
        hasher.combine(citations ?? [])
        return hasher.finalize()
    }
}
