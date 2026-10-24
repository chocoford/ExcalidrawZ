//
//  ExcalidrawModelProfileOption.swift
//  ExcalidrawZ
//
//  Created by Codex on 6/13/26.
//

import Foundation
import LLMCore

struct ExcalidrawModelProfileOption: Identifiable, Equatable {
    let profileID: String
    let tier: ExcalidrawModelTier
    let model: SupportedModel
    let rank: Int
    let isVisible: Bool
    let requiresMaxAIPlan: Bool
    let supportsImageInput: Bool
    let maxContextTokens: Int?

    var id: String { profileID }
    var title: String { tier.name }
}

/// Request capabilities are independent of platform tiers when using a user-supplied model.
struct AIChatModelSelection {
    let model: SupportedModel
    let profileID: String?
    let supportsImageInput: Bool
    let maxContextTokens: Int?

    init(platform option: ExcalidrawModelProfileOption) {
        model = option.model
        profileID = option.profileID
        supportsImageInput = option.supportsImageInput
        maxContextTokens = option.maxContextTokens
    }

    init(byok model: SupportedModel) {
        self.model = model
        profileID = nil
        // The upstream validates capabilities; unknown IDs must not silently lose attachments.
        supportsImageInput = true
        maxContextTokens = nil
    }
}

extension ExcalidrawModelTier {
    init?(profileID: String) {
        self.init(rawValue: profileID)
    }
}

extension ModelProfileRequirements {
    var requiresExcalidrawMaxAIPlan: Bool {
        plan == "max"
    }
}

extension DomainModelProfile {
    var excalidrawModelProfileOption: ExcalidrawModelProfileOption? {
        guard let tier = ExcalidrawModelTier(profileID: id) else { return nil }
        return ExcalidrawModelProfileOption(
            profileID: id,
            tier: tier,
            model: model,
            rank: rank,
            isVisible: isVisible,
            requiresMaxAIPlan: requirements.requiresExcalidrawMaxAIPlan,
            supportsImageInput: capabilities.supportsImageInput ?? model.supportsExcalidrawImageInput,
            maxContextTokens: capabilities.maxContextTokens ?? model.maxContextTokens
        )
    }
}

extension DomainAgentConfigResponse {
    var excalidrawModelOptions: [ExcalidrawModelProfileOption] {
        modelProfiles?.compactMap(\.excalidrawModelProfileOption) ?? []
    }
}
