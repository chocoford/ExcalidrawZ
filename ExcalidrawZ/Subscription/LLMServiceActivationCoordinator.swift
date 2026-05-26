//
//  LLMServiceActivationCoordinator.swift
//  ExcalidrawZ
//

import Foundation
import Logging
import LLMKit

actor LLMServiceActivationCoordinator {
    static let shared = LLMServiceActivationCoordinator()

    enum Reason: String, Sendable {
        case appLaunch
        case aiEnabledChanged
        case aiSettingsAppear
        case aiChatEnable
    }

    private let logger = Logger(label: "LLMServiceActivationCoordinator")
    private var restoreTask: Task<Void, Never>?
    private var restoreGeneration = 0
    private var hasRestoredForCurrentEnabledSession = false

    func restoreIfAIEnabled(reason: Reason) async {
        guard AIChatAvailability.isAvailable else {
            restoreGeneration += 1
            restoreTask?.cancel()
            restoreTask = nil
            hasRestoredForCurrentEnabledSession = false
            logger.debug("[LLMService] restore skipped reason=\(reason.rawValue) aiAvailable=false")
            return
        }

        guard isAIEnabled else {
            hasRestoredForCurrentEnabledSession = false
            logger.debug("[LLMService] restore skipped reason=\(reason.rawValue) aiDisabled=true")
            return
        }

        guard !hasRestoredForCurrentEnabledSession else {
            logger.debug("[LLMService] restore skipped reason=\(reason.rawValue) alreadyRestored=true")
            return
        }

        if let restoreTask {
            logger.debug("[LLMService] restore coalesced reason=\(reason.rawValue)")
            await restoreTask.value
            return
        }

        restoreGeneration += 1
        let generation = restoreGeneration
        let task = Task {
            await LLMClient.shared.restore()
        }
        restoreTask = task
        await task.value

        guard restoreGeneration == generation else {
            logger.debug("[LLMService] restore ignored reason=\(reason.rawValue) generationChanged=true")
            return
        }

        restoreTask = nil

        guard isAIEnabled else {
            hasRestoredForCurrentEnabledSession = false
            logger.info("[LLMService] restore completed but AI is disabled reason=\(reason.rawValue)")
            return
        }

        hasRestoredForCurrentEnabledSession = true
        logger.info("[LLMService] restore completed reason=\(reason.rawValue)")
    }

    func handleAIEnabledChanged(_ enabled: Bool) async {
        guard enabled else {
            restoreGeneration += 1
            restoreTask?.cancel()
            restoreTask = nil
            hasRestoredForCurrentEnabledSession = false
            logger.info("[LLMService] AI disabled")
            return
        }

        await restoreIfAIEnabled(reason: .aiEnabledChanged)
    }

    private var isAIEnabled: Bool {
        UserDefaults.standard.object(forKey: AIChatPreferences.isAIEnabledDefaultsKey) as? Bool ?? false
    }
}
