import Foundation
import LLMCore
import LLMKit
import XCTest
@testable import ExcalidrawZ

final class AIInferenceBuildPolicyTests: XCTestCase {
    @MainActor
    func testNewManagedBuildDefaultsToBasicAndPersistsTransport() throws {
        let defaults = BuildPolicyMemoryDefaults()
        let state = AIInferenceBillingState(defaults: defaults, keyStore: BuildPolicyMemoryKeys(), supportsManagedInference: true)
        XCTAssertEqual(state.integrationMode, .basic)
        XCTAssertEqual(defaults.string(forKey: AIInferenceBillingState.integrationModeDefaultsKey), "basic")
        try state.setMode(.byok)
        XCTAssertEqual(state.integrationMode, .basic, "First-time BYOK activation must not require a paid transport")
        XCTAssertThrowsError(try state.resolveSelection(), "A missing connection must not fall back to the platform")
    }

    @MainActor
    func testLegacyConnectionWithoutTransportKeepsOptimized() throws {
        let defaults = BuildPolicyMemoryDefaults()
        let keys = BuildPolicyMemoryKeys()
        let original = AIInferenceBillingState(defaults: defaults, keyStore: keys, supportsManagedInference: true)
        try original.setMode(.byok)
        let profile = try original.addConnection(.openAI, apiKey: "synthetic-key")
        defaults.set(nil, forKey: AIInferenceBillingState.integrationModeDefaultsKey)

        let restored = AIInferenceBillingState(defaults: defaults, keyStore: keys, supportsManagedInference: true)
        XCTAssertEqual(restored.integrationMode, .optimized)
        XCTAssertEqual(defaults.string(forKey: AIInferenceBillingState.integrationModeDefaultsKey), "optimized")
        XCTAssertEqual(restored.selectedProfileID, profile.id)
        XCTAssertEqual(try restored.keyForEditing(), "synthetic-key")
    }

    @MainActor
    func testDirectOnlyBuildPreservesConnectionWhileDroppingManagedTransport() throws {
        let defaults = BuildPolicyMemoryDefaults()
        let keys = BuildPolicyMemoryKeys()
        let original = AIInferenceBillingState(defaults: defaults, keyStore: keys, supportsManagedInference: true)
        try original.setMode(.byok)
        let profile = try original.addConnection(.openAI, apiKey: "synthetic-key")
        try original.setModel("provider-model")
        defaults.set(AIInferenceIntegrationMode.optimized.rawValue, forKey: AIInferenceBillingState.integrationModeDefaultsKey)

        let direct = AIInferenceBillingState(defaults: defaults, keyStore: keys, supportsManagedInference: false)
        XCTAssertEqual(direct.mode, .byok)
        XCTAssertEqual(direct.integrationMode, .basic)
        XCTAssertEqual(defaults.string(forKey: AIInferenceBillingState.integrationModeDefaultsKey), "basic")
        XCTAssertEqual(direct.selectedProfileID, profile.id)
        XCTAssertEqual(try direct.keyForEditing(), "synthetic-key")
        XCTAssertEqual(try direct.modelForChat().rawValue, "provider-model")
        XCTAssertFalse(direct.requiresBillingSelection)

        XCTAssertThrowsError(try direct.setMode(.platform)) { error in
            guard case AIInferenceBillingError.managedInferenceUnavailable = error else { return XCTFail("Unexpected error: \(error)") }
        }
        XCTAssertThrowsError(try direct.setIntegrationMode(.optimized))
        let reads = keys.readCount
        XCTAssertThrowsError(try direct.resolveSelection(for: .init(
            selection: .init(schemeID: "excalidraw-canvas", profileID: "medium"), billing: .platform)))
        XCTAssertThrowsError(try direct.resolveSelection(for: .init(
            selection: .init(schemeID: "excalidraw-canvas"), billing: .byok(model: .other("provider-model")), connectionID: profile.id)))
        XCTAssertEqual(keys.readCount, reads, "Reject server routes before reading a provider key")
        XCTAssertEqual(direct.integrationMode, .basic)
        XCTAssertEqual(direct.mode, .byok)
    }

    @MainActor
    func testDirectOnlyBuildRequiresExplicitChoiceForOldPlatformSettings() throws {
        let defaults = BuildPolicyMemoryDefaults()
        defaults.set("platform", forKey: AIInferenceBillingState.modeDefaultsKey)
        let state = AIInferenceBillingState(defaults: defaults, keyStore: BuildPolicyMemoryKeys(), supportsManagedInference: false)
        XCTAssertTrue(state.requiresBillingSelection)
        XCTAssertThrowsError(try state.resolveSelection())
        try state.setMode(.byok)
        XCTAssertFalse(state.requiresBillingSelection)
        XCTAssertEqual(state.integrationMode, .basic)
        XCTAssertThrowsError(try state.resolveSelection(), "An unconfigured Basic connection must not fall back to the platform")
    }

    @MainActor
    func testManagedBuildKeepsExistingTransportAndPlatformChoice() throws {
        let defaults = BuildPolicyMemoryDefaults()
        defaults.set("optimized", forKey: AIInferenceBillingState.integrationModeDefaultsKey)
        defaults.set("platform", forKey: AIInferenceBillingState.modeDefaultsKey)
        let state = AIInferenceBillingState(defaults: defaults, keyStore: BuildPolicyMemoryKeys(), supportsManagedInference: true)
        XCTAssertFalse(state.requiresBillingSelection)
        XCTAssertEqual(state.mode, .platform)
        XCTAssertEqual(state.integrationMode, .optimized)
        XCTAssertNil(try state.resolveSelection().credentials)
    }
}

private final class BuildPolicyMemoryDefaults: UserDefaults {
    private var values: [String: Any] = [:]
    override func object(forKey key: String) -> Any? { values[key] }
    override func string(forKey key: String) -> String? { values[key] as? String }
    override func dictionary(forKey key: String) -> [String: Any]? { values[key] as? [String: Any] }
    override func set(_ value: Any?, forKey key: String) { values[key] = value }
}

private final class BuildPolicyMemoryKeys: AIInferenceKeyStoring {
    private var keys: [String: String] = [:]
    private(set) var readCount = 0
    func readKey(for account: String) throws -> String? { readCount += 1; return keys[account] }
    func saveKey(_ key: String, for account: String) throws { keys[account] = key }
    func removeKey(for account: String) throws { keys[account] = nil }
}
