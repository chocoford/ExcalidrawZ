//
//  ExcalidrawModelProfileOption.swift
//  ExcalidrawZ
//
//  Created by Codex on 6/13/26.
//

import Foundation
import LLMCore

struct ExcalidrawModelProfileOption: Identifiable, Equatable {
    let profile: LLMSchemeProfile

    var id: String { profile.id }
    var profileID: String { profile.id }
    var title: String { profile.name }
    var isVisible: Bool { profile.isVisible }
    var isAllowed: Bool { profile.access?.allowed ?? true }
    var supportsImageInput: Bool { profile.capabilities.supportsImageInput ?? false }
    var maxContextTokens: Int? { profile.capabilities.maxContextTokens }
    // A local AgentExecutor hint; never selects the server's model.
    var model: SupportedModel { .other(profile.modelID ?? "scheme-profile") }
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

    init(legacy model: SupportedModel, profileID: String? = nil,
         supportsImageInput: Bool? = nil, maxContextTokens: Int? = nil) {
        self.model = model
        self.profileID = profileID
        self.supportsImageInput = supportsImageInput ?? model.supportsImageInput
        self.maxContextTokens = maxContextTokens ?? model.maxContextTokens
    }

    init(byok model: SupportedModel) {
        self.model = model
        profileID = nil
        // The upstream validates capabilities; unknown IDs must not silently lose attachments.
        supportsImageInput = true
        maxContextTokens = nil
    }
}

extension LLMSchemeDescriptor {
    var excalidrawModelOptions: [ExcalidrawModelProfileOption] {
        profiles.filter { $0.isVisible && $0.access?.allowed != false }.sorted {
            $0.rank == $1.rank ? $0.id < $1.id : $0.rank < $1.rank
        }.map { ExcalidrawModelProfileOption(profile: $0) }
    }
}
