import Foundation
import LLMCore
import LLMKit

/// Extra App-owned connection identity accompanying the SDK's non-secret Direct binding.
struct AIDirectConversationRecord: Codable, Equatable, Sendable {
    let connectionID: String
    var binding: LLMDirectConversationBinding

    func validate() throws {
        guard !connectionID.isEmpty, connectionID.utf8.count <= 512,
              connectionID.utf8.allSatisfy({ (33...126).contains($0) }),
              !binding.chatModel.rawValue.isEmpty, binding.chatModel.rawValue.utf8.count <= 512,
              binding.chatModel.rawValue.utf8.allSatisfy({ (33...126).contains($0) }) else {
            throw AIChatRoutingError.invalidRoute
        }
        try binding.configuration.validate()
        _ = try binding.configuration.modelMapping.resolve(binding.chatModel.rawValue)
    }
}

/// Missing data is a legacy route. Malformed data must never become a legacy/platform call.
enum AIChatRouteStorage {
    static func encode(_ binding: LLMSchemeConversationBinding?) throws -> Data? {
        guard let binding else { return nil }
        try binding.validate()
        return try JSONEncoder().encode(binding)
    }

    static func decode(_ data: Data?) throws -> LLMSchemeConversationBinding? {
        guard let data else { return nil }
        if try directEnvelope(data) != nil { return nil }
        let binding = try JSONDecoder().decode(LLMSchemeConversationBinding.self, from: data)
        try binding.validate()
        return binding
    }
    private struct DirectEnvelope: Codable { let direct: AIDirectConversationRecord }

    static func encodeDirect(_ record: AIDirectConversationRecord) throws -> Data {
        try record.validate()
        return try JSONEncoder().encode(DirectEnvelope(direct: record))
    }

    private static func directEnvelope(_ data: Data) throws -> AIDirectConversationRecord? {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AIChatRoutingError.invalidRoute
        }
        guard object.keys.contains("direct") else { return nil }
        guard object.count == 1 else { throw AIChatRoutingError.invalidRoute }
        let record = try JSONDecoder().decode(DirectEnvelope.self, from: data).direct
        try record.validate()
        return record
    }

    static func decodeDirect(_ data: Data?) throws -> AIDirectConversationRecord? {
        guard let data else { return nil }
        if let record = try directEnvelope(data) { return record }
        _ = try decode(data)
        return nil
    }

}
