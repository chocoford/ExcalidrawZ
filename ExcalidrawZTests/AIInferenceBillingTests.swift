import Foundation
import XCTest
import LLMKit
import LLMCore
@testable import ExcalidrawZ

final class AIInferenceBillingTests: XCTestCase {
    func testSDKSchemeBindingRoundTripsWithoutCredentialsAndRejectsCorruptData() throws {
        let bindings: [LLMSchemeConversationBinding] = [
            .init(selection: .init(schemeID: "excalidraw-canvas", profileID: "extra-high"), billing: .platform),
            .init(selection: .init(schemeID: "excalidraw-canvas", profileID: "fifth-profile"), billing: .platform),
            .init(selection: .init(schemeID: "excalidraw-canvas"), billing: .byok(model: .other("provider/new-model")), connectionID: "work"),
            .init(selection: .init(schemeID: "excalidraw-canvas"), billing: .byok(model: .gpt4o), connectionID: "work")
        ]
        for binding in bindings {
            let data = try XCTUnwrap(AIChatRouteStorage.encode(binding))
            XCTAssertEqual(try AIChatRouteStorage.decode(data), binding)
            XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("apiKey"))
            XCTAssertEqual(try AIChatConversationRoute(binding: binding).binding, binding)
        }
        XCTAssertNil(try AIChatRouteStorage.decode(nil))
        XCTAssertNil(try AIChatRouteStorage.encode(nil))
        XCTAssertEqual(try AIChatConversationRoute(binding: nil), .legacy)
        XCTAssertThrowsError(try AIChatRouteStorage.decode(Data("bad-json".utf8)))
        XCTAssertEqual(bindings[0].selection.profileID, "extra-high")
        XCTAssertNil(bindings[2].selection.profileID)
        let knownOther = LLMSchemeConversationBinding(selection: .init(schemeID: "excalidraw-canvas"),
            billing: .byok(model: .other(SupportedModel.gpt4o.rawValue)), connectionID: "work")
        let restored = try AIChatRouteStorage.decode(AIChatRouteStorage.encode(knownOther))
        XCTAssertEqual(try AIChatConversationRoute(binding: restored), try AIChatConversationRoute(binding: knownOther))
        let invalid = LLMSchemeConversationBinding(selection: .init(schemeID: "canvas"), billing: .platform)
        XCTAssertThrowsError(try AIChatRouteStorage.encode(invalid))
        XCTAssertThrowsError(try AIChatRouteStorage.decode(JSONEncoder().encode(invalid)))
    }

    func testDashboardProfilesHaveNoFixedTierLimitOrClientPlanMapping() {
        let scheme = LLMSchemeDescriptor(
            id: "excalidraw-canvas", name: "Canvas", summary: "", kind: .conversation,
            defaultProfileID: "fifth-profile", profiles: [
                .init(id: "fifth-profile", name: "Custom Fifth", rank: 50),
                .init(id: "extra-high", name: "Powerful", rank: 10, access: .init(allowed: true)),
                .init(id: "hidden", name: "Hidden", rank: 0, isVisible: false)
            ]
        )
        let options = scheme.excalidrawModelOptions
        XCTAssertEqual(options.map(\.profileID), ["extra-high", "fifth-profile"])
        XCTAssertEqual(options.map(\.title), ["Powerful", "Custom Fifth"])
        XCTAssertTrue(options[0].isAllowed)
        XCTAssertTrue(options[1].isAllowed)
    }

    func testDashboardDeniedProfilesAreAbsentFromModelMenus() {
        var scheme = LLMSchemeDescriptor(
            id: "excalidraw-canvas", name: "Canvas", summary: "", kind: .conversation,
            defaultProfileID: "medium", profiles: [
                .init(id: "low", name: "Low", rank: 10, access: .denied(.subscriptionRequired)),
                .init(id: "medium", name: "Medium", rank: 20, access: .denied(.subscriptionRequired)),
                .init(id: "high", name: "High", rank: 30, access: .denied(.subscriptionRequired)),
                .init(id: "extra-high", name: "Extra High", rank: 40, access: .denied(.explicitDeny))
            ]
        )
        XCTAssertTrue(scheme.excalidrawModelOptions.isEmpty)

        for index in 0..<3 { scheme.profiles[index].access = .init(allowed: true) }
        XCTAssertEqual(scheme.excalidrawModelOptions.map(\.profileID), ["low", "medium", "high"])
        XCTAssertEqual(scheme.profiles.count, 4, "Keep metadata for existing conversation routes")
    }

    func testDashboardPermissionChangesDoNotSilentlyReplaceSavedProfile() {
        var scheme = LLMSchemeDescriptor(
            id: "excalidraw-canvas", name: "Canvas", summary: "", kind: .conversation,
            defaultProfileID: "extra-high", profiles: [
                .init(id: "medium", name: "Medium", rank: 20, access: .init(allowed: true)),
                .init(id: "extra-high", name: "Extra High", rank: 40, access: .init(allowed: true))
            ]
        )
        XCTAssertEqual(scheme.excalidrawModelOptions.map(\.profileID), ["medium", "extra-high"])

        scheme.profiles[1].access = .denied(.explicitDeny)
        XCTAssertEqual(scheme.excalidrawModelOptions.map(\.profileID), ["medium"])
        XCTAssertEqual(scheme.defaultProfileID, "extra-high")
    }

    @MainActor
    func testSavedBYOKRouteUsesItsOwnConnectionAfterGlobalSettingsChange() async throws {
        let (_, keys, state) = fixture()
        try state.setMode(.byok)
        let first = try state.addConnection(.openAI, apiKey: "first-key")
        let route = LLMSchemeConversationBinding(selection: .init(schemeID: "excalidraw-canvas"),
            billing: .byok(model: .other("own-model")), connectionID: first.id)
        _ = try state.addConnection(.openRouter, apiKey: "second-key")
        try state.setMode(.platform)
        let snapshot = try state.resolveSelection(for: route)
        XCTAssertEqual(snapshot.credentials?.configuration.baseURL, LLMBYOKConfiguration.openAI.baseURL)
        XCTAssertEqual(snapshot.credentials?.configuration.defaultModel, "own-model")
        let reads = keys.readCount
        XCTAssertNil(try state.resolveSelection(for: .init(selection: .init(schemeID: "canvas", profileID: "fifth"), billing: .platform)).credentials)
        XCTAssertEqual(keys.readCount, reads, "Platform routing must not read any provider key")
        try await state.withBillingSnapshot(snapshot) {
            XCTAssertEqual(try state.modelForAuxiliaryRequest(fallback: .gpt4oMini).rawValue, "own-model")
        }
        keys.keys[first.id] = nil
        XCTAssertThrowsError(try state.resolveSelection(for: route), "Missing saved key cannot select another connection")
        XCTAssertThrowsError(try state.resolveSelection(for: .init(selection: .init(schemeID: "canvas"),
            billing: .byok(model: .other("own-model")))))
    }

    @MainActor
    func testBoundModelDiscoveryUsesSavedConnectionAfterGlobalSelectionChanges() async throws {
        let (_, _, state) = fixture()
        try state.setMode(.byok)
        let first = try state.addConnection(.openAI, apiKey: "first-synthetic-key")
        _ = try state.addConnection(.openRouter, apiKey: "other-synthetic-key")
        try state.setMode(.platform)
        let fetcher = ModelCatalogFetchStub()
        let catalog = AIInferenceModelCatalog { provider, _ in try await fetcher.fetch(provider) }
        await catalog.load(for: state, profileID: first.id, force: true)
        XCTAssertEqual(catalog.snapshot(for: state, profileID: first.id).models.map(\.id), ["first-model", "second-model"])
        XCTAssertTrue(catalog.snapshot(for: state).models.isEmpty)
        let count = await fetcher.count
        XCTAssertEqual(count, 1)
        try state.removeConnection(first.id)
        XCTAssertThrowsError(try state.credentials(connectionID: first.id, model: .other("own-model")))
    }

    @MainActor
    func testBasicIntegrationUsesDirectDiscoveryAndBlocksBackendCredentials() async throws {
        let (defaults, _, state) = fixture()
        try state.saveKey("synthetic-key")
        try state.setMode(.byok)
        let profileID = try XCTUnwrap(state.selectedProfileID)
        try state.setIntegrationMode(.basic)
        XCTAssertNotNil(try state.resolveSelection().credentials)
        XCTAssertNotNil(try state.modelDiscoveryProvider())
        let restored = AIInferenceBillingState(defaults: defaults, keyStore: MemoryKeyStore())
        XCTAssertEqual(restored.integrationMode, .basic)
        XCTAssertEqual(restored.selectedProfileID, profileID)

        let snapshot = try state.directSnapshot(connectionID: profileID, modelID: "own-model")
        XCTAssertFalse(String(reflecting: snapshot).contains("synthetic-key"))
        try await state.withDirectBilling(snapshot) {
            XCTAssertEqual(try snapshot.key(for: profileID, configuration: snapshot.configuration), "synthetic-key")
            XCTAssertThrowsError(try state.setIntegrationMode(.optimized))
            do {
                _ = try await AIInferenceBilling.credentialsForRequest(for: .other("own-model"))
                XCTFail("Direct must not supply a provider key to backend inference")
            } catch LLMDirectError.unsupportedCapability {}
        }
        let fetcher = ModelCatalogFetchStub()
        let catalog = AIInferenceModelCatalog { provider, mode in
            XCTAssertEqual(mode, .basic)
            return try await fetcher.fetch(provider)
        }
        await catalog.load(for: state, force: true)
        XCTAssertFalse(catalog.snapshot(for: state).models.isEmpty)
        let fetchCount = await fetcher.count
        XCTAssertEqual(fetchCount, 1)
        defaults.set("unknown-route", forKey: AIInferenceBillingState.integrationModeDefaultsKey)
        let unknown = AIInferenceBillingState(defaults: defaults, keyStore: MemoryKeyStore())
        XCTAssertEqual(unknown.integrationMode, .basic)
        try state.setMode(.platform)
        XCTAssertNil(try state.resolveSelection().credentials)
    }

    func testProviderListIncludesEverySDKPresetInPreferredOrder() throws {
        let connections = AIInferenceConnection.allCases
        XCTAssertEqual(Array(connections.prefix(4)), [.openAI, .anthropic, .gemini, .openRouter])
        XCTAssertEqual(connections.last, .custom)
        XCTAssertEqual(Set(connections.filter { $0 != .custom }.map(\.rawValue)),
                       Set(LLMBYOKPreset.allCases.map(\.rawValue)))
        XCTAssertEqual(connections.count, LLMBYOKPreset.allCases.count + 1)

        for preset in LLMBYOKPreset.allCases {
            let connection = try XCTUnwrap(AIInferenceConnection(rawValue: preset.rawValue))
            XCTAssertEqual(connection.title, preset.displayName)
            XCTAssertEqual(connection.presetConfiguration, preset.configuration)
            XCTAssertNotNil(connection.presetConfiguration?.modelDiscovery)
        }
    }

    func testProviderCodingPreservesExistingProfileStrings() throws {
        for connection in AIInferenceConnection.allCases {
            let encoded = try JSONEncoder().encode(connection)
            XCTAssertEqual(encoded, try JSONEncoder().encode(connection.rawValue))
            XCTAssertEqual(try JSONDecoder().decode(AIInferenceConnection.self, from: encoded), connection)
        }
        let legacyProfile = Data(#"{"id":"existing-account","name":"Work","provider":"openai","configuration":null}"#.utf8)
        let profile = try JSONDecoder().decode(AIInferenceConnectionProfile.self, from: legacyProfile)
        XCTAssertEqual(profile.id, "existing-account")
        XCTAssertEqual(profile.provider, .openAI)
        XCTAssertNil(profile.configuration)
        XCTAssertNil(AIInferenceConnection(rawValue: "unknown-provider"))
        XCTAssertThrowsError(try JSONDecoder().decode(AIInferenceConnection.self, from: Data(#""unknown-provider""#.utf8)))
    }

    @MainActor
    func testSDKPresetsPersistWithIndependentKeysAndModels() async throws {
        let defaults = MemoryDefaults()
        let store = MemoryKeyStore()
        let state = AIInferenceBillingState(defaults: defaults, keyStore: store)
        try state.setMode(.byok)
        for preset in LLMBYOKPreset.allCases {
            let connection = AIInferenceConnection.preset(preset)
            let profile = try state.addConnection(connection, apiKey: "synthetic-\(preset.rawValue)-key")
            try state.setModel("provider-model-\(preset.rawValue)")
            XCTAssertEqual(profile.configuration, preset.configuration)
        }
        let restored = AIInferenceBillingState(defaults: defaults, keyStore: store)
        XCTAssertEqual(restored.profiles.count, LLMBYOKPreset.allCases.count)
        for profile in restored.profiles {
            try restored.selectConnection(profile.id)
            XCTAssertEqual(try restored.keyForEditing(), "synthetic-\(profile.provider.rawValue)-key")
            XCTAssertEqual(try restored.resolveSelection().credentials?.configuration.defaultModel,
                           "provider-model-\(profile.provider.rawValue)")
        }
    }

    @MainActor
    func testCustomConnectionWithoutDiscoveryDoesNotFetchModelsOrReportAnError() async throws {
        let (_, _, state) = fixture()
        try state.setMode(.byok)
        let configuration = LLMBYOKConfiguration(
            baseURL: URL(string: "https://gateway.example.com/v1/")!, modelDiscovery: nil
        )
        try state.addConnection(.custom, configuration: configuration, apiKey: "synthetic-custom-key")
        let fetcher = ModelCatalogFetchStub()
        let catalog = AIInferenceModelCatalog { provider, _ in try await fetcher.fetch(provider) }
        await catalog.load(for: state, force: true)
        let fetchCount = await fetcher.count
        XCTAssertEqual(fetchCount, 0)
        XCTAssertNil(catalog.snapshot(for: state).errorMessage)
        XCTAssertFalse(catalog.snapshot(for: state).isLoading)
        try state.setModel("accounts/example/models/chat-model")
        XCTAssertEqual(try state.modelForChat().rawValue, "accounts/example/models/chat-model")
    }

    @MainActor
    func testRemovedPresetProfilesRetainTheirSavedConfigurationAndKey() async throws {
        for retired in ["fireworks", "zai", "zhipu", "volcengine"] {
            let defaults = MemoryDefaults()
            let store = MemoryKeyStore()
            let configuration = LLMBYOKConfiguration(
                baseURL: URL(string: "https://gateway.example.com/v1/")!, modelDiscovery: nil
            )
            let profile: [String: Any] = [
                "id": "existing-account", "name": "Existing", "provider": retired,
                "configuration": try JSONSerialization.jsonObject(with: JSONEncoder().encode(configuration)),
                "lastModelID": "existing-model",
            ]
            let data = try JSONSerialization.data(withJSONObject: ["profiles": [profile], "selectedID": "existing-account"])
            defaults.set(data, forKey: AIInferenceBillingState.profilesDefaultsKey)
            defaults.set("byok", forKey: AIInferenceBillingState.modeDefaultsKey)
            store.keys["existing-account"] = "synthetic-existing-key"
            let restored = AIInferenceBillingState(defaults: defaults, keyStore: store)
            XCTAssertFalse(restored.configurationLoadFailed)
            XCTAssertEqual(restored.selectedProfile?.provider, .custom)
            XCTAssertEqual(restored.configuration, configuration)
            XCTAssertEqual(try restored.keyForEditing(), "synthetic-existing-key")
            XCTAssertEqual(try restored.modelForChat().rawValue, "existing-model")
        }
    }

    @MainActor
    func testOldMiniMaxDefaultsGainDiscoveryWithoutChangingCustomizedConnections() async throws {
        for provider in [AIInferenceConnection.preset(.miniMax), .preset(.miniMaxChina)] {
            let defaults = MemoryDefaults()
            let store = MemoryKeyStore()
            let state = AIInferenceBillingState(defaults: defaults, keyStore: store)
            let preset = try XCTUnwrap(provider.presetConfiguration)
            var previous = preset
            previous.modelDiscovery = nil
            let account = try state.addConnection(provider, configuration: previous, apiKey: "synthetic-minimax-key")
            try state.setModel("existing-model")
            var customized = previous
            customized.baseURL = URL(string: "https://gateway.example.com/v1/")!
            let customAccount = try state.addConnection(provider, configuration: customized, apiKey: "synthetic-custom-key")
            let restored = AIInferenceBillingState(defaults: defaults, keyStore: store)
            XCTAssertEqual(restored.profiles.first { $0.id == account.id }?.configuration, preset)
            XCTAssertEqual(restored.profiles.first { $0.id == account.id }?.lastModelID, "existing-model")
            XCTAssertEqual(restored.profiles.first { $0.id == customAccount.id }?.configuration, customized)
            XCTAssertEqual(try restored.keyForEditing(profileID: account.id), "synthetic-minimax-key")
            XCTAssertEqual(restored.selectedProfileID, customAccount.id)
        }
    }

    @MainActor
    func testPlatformRequestsDoNotRequireOrReadAKey() async throws {
        let (_, store, state) = fixture()
        let reads = store.readCount
        XCTAssertNil(try state.resolveSelection().credentials)
        XCTAssertEqual(store.readCount, reads)
        XCTAssertFalse(state.usesBYOK)
    }

    @MainActor
    func testCredentialsAreNeverWrittenToPreferences() async throws {
        let (defaults, store, state) = fixture()
        try state.saveKey("  synthetic-openrouter-key  ")
        try state.setMode(.byok)
        XCTAssertEqual(store.key, "synthetic-openrouter-key")
        XCTAssertEqual(defaults.string(forKey: AIInferenceBillingState.modeDefaultsKey), "byok")
        XCTAssertFalse(String(describing: defaults.values).contains("synthetic-openrouter-key"))

        let restored = AIInferenceBillingState(defaults: defaults, keyStore: store)
        XCTAssertTrue(restored.usesBYOK)
        XCTAssertTrue(restored.hasStoredKey)
    }

    @MainActor
    func testMissingKeyNeverSelectsPlatformBilling() async throws {
        let (_, _, state) = fixture()
        try state.setMode(.byok)
        do {
            _ = try state.resolveSelection()
            XCTFail("BYOK without a key must fail")
        } catch AIInferenceBillingError.missingKey {
        }
        XCTAssertTrue(state.usesBYOK)
    }

    @MainActor
    func testRemovingKeyPreservesSelectedBillingMode() async throws {
        let (_, store, state) = fixture()
        try state.saveKey("synthetic-key")
        try state.setMode(.byok)
        try state.removeKey()
        XCTAssertNil(store.key)
        XCTAssertFalse(state.hasStoredKey)
        XCTAssertTrue(state.usesBYOK)
        XCTAssertThrowsError(try state.resolveSelection())
    }

    @MainActor
    func testKeychainFailureDoesNotFallBack() async throws {
        let (_, store, state) = fixture()
        try state.setMode(.byok)
        store.readFailure = FixtureError.failed
        state.refreshKeyStatus()
        XCTAssertTrue(state.isKeychainUnavailable)
        XCTAssertThrowsError(try state.resolveSelection())
        XCTAssertTrue(state.usesBYOK)
    }

    @MainActor
    func testInvalidKeysDoNotReplaceSavedKey() async throws {
        let (_, store, state) = fixture()
        try state.saveKey("synthetic-key")
        for invalid in ["", "  ", "key\r\nInjected: value", "key value", String(repeating: "x", count: 4097)] {
            XCTAssertThrowsError(try state.saveKey(invalid))
            XCTAssertEqual(store.key, "synthetic-key")
        }
    }

    @MainActor
    func testBillingAndKeyCannotChangeDuringAnOperation() async throws {
        let (_, _, state) = fixture()
        try state.saveKey("synthetic-key")
        try state.setMode(.byok)
        try await state.withSelectedBilling {
            XCTAssertTrue(state.isBusy)
            XCTAssertThrowsError(try state.setMode(.platform))
            XCTAssertThrowsError(try state.saveKey("replacement"))
            XCTAssertThrowsError(try state.removeKey())
            XCTAssertThrowsError(try state.addConnection(.openAI))
            XCTAssertThrowsError(try state.saveConfiguration(.openRouter))
            XCTAssertThrowsError(try state.setModel("replacement-model", for: "conversation"))
            let credentials = try await AIInferenceBilling.credentialsForRequest(for: .gpt4oMini)
            XCTAssertNotNil(credentials)
        }
        XCTAssertFalse(state.isBusy)
        XCTAssertEqual(state.activeOperationCount, 0)
        XCTAssertNil(AIInferenceBilling.selection)
    }

    @MainActor
    func testChangedSelectionRejectsPreparedRequestsBeforeReadingCredentials() async throws {
        let (_, store, state) = fixture()
        try state.saveKey("synthetic-key")
        try state.setMode(.byok)
        let original = try XCTUnwrap(state.selectedProfileID)
        let other = try state.addConnection(.openAI, apiKey: "synthetic-other-key")
        try state.selectConnection(original)

        let changes: [() throws -> Void] = [
            { try state.selectConnection(other.id) },
            { try state.saveKey("synthetic-replacement") },
            { try state.setMode(.platform) },
            { try state.setMode(.byok) },
        ]
        for change in changes {
            let revision = state.modelCatalogRevision
            try change()
            let readCount = store.readCount
            do {
                try await state.withSelectedBilling(expectedRevision: revision) {
                    XCTFail("A prepared request must not use a changed connection")
                }
                XCTFail("Expected the selection change to reject the request")
            } catch AIInferenceBillingError.selectionChanged {
            }
            XCTAssertEqual(store.readCount, readCount)
            XCTAssertFalse(state.isBusy)
            XCTAssertNil(AIInferenceBilling.selection)
        }

        let revision = state.modelCatalogRevision
        try state.setModel("provider-model")
        try await state.withSelectedBilling(expectedRevision: revision) {
            let credentials = try await AIInferenceBilling.credentialsForRequest(for: .other("provider-model"))
            XCTAssertEqual(credentials?.configuration.baseURL, LLMBYOKConfiguration.openAI.baseURL)
            XCTAssertTrue(state.isBusy)
        }
        XCTAssertFalse(state.isBusy)
    }

    @MainActor
    func testChildRequestsKeepTheSnapshotAfterSettingsChange() async throws {
        let (_, store, state) = fixture()
        try state.saveKey("synthetic-key")
        try state.setMode(.byok)
        let expectedConfiguration = try state.resolveSelection().credentials?.configuration
        var continuation: AsyncStream<Void>.Continuation!
        let gate = AsyncStream<Void> { continuation = $0 }
        let child = try await state.withSelectedBilling {
            Task {
                for await _ in gate { break }
                return try await AIInferenceBilling.credentialsForRequest(for: .gpt4oMini)
            }
        }
        try state.setMode(.platform)
        try state.removeKey()
        let readCount = store.readCount
        continuation.yield(())
        continuation.finish()
        let credentials = try await child.value
        XCTAssertNotNil(credentials)
        XCTAssertEqual(credentials?.configuration, expectedConfiguration)
        XCTAssertEqual(store.readCount, readCount)
        XCTAssertFalse(String(reflecting: credentials).contains("synthetic-key"))
    }

    @MainActor
    func testFailedOperationsReleaseTheSettingsLock() async throws {
        let (_, _, state) = fixture()
        do {
            try await state.withSelectedBilling {
                throw FixtureError.failed
            }
            XCTFail("Expected operation failure")
        } catch FixtureError.failed {
        }
        XCTAssertFalse(state.isBusy)
        XCTAssertNil(AIInferenceBilling.selection)
        try state.setMode(.byok)
    }

    @MainActor
    func testUnknownStoredModeRequiresAnExplicitBillingChoice() async throws {
        let defaults = MemoryDefaults()
        defaults.set("unsupported-provider", forKey: AIInferenceBillingState.modeDefaultsKey)
        let state = AIInferenceBillingState(defaults: defaults, keyStore: MemoryKeyStore())
        XCTAssertTrue(state.requiresBillingSelection)
        XCTAssertThrowsError(try state.resolveSelection())
        try state.setMode(.platform)
        XCTAssertFalse(state.requiresBillingSelection)
        XCTAssertNil(try state.resolveSelection().credentials)
    }

    @MainActor
    func testOpenRouterCreditErrorsHaveTheirOwnPresentation() async throws {
        let error = LLMError.server(
            statusCode: 502,
            message: "Your BYOK provider account has insufficient credits."
        )
        XCTAssertNotNil(AIInferenceErrorMessage.localizedError(for: error))
        XCTAssertNil(AIInferenceErrorMessage.localizedError(for: LLMError.insufficientCredits))
        XCTAssertNil(AIInferenceErrorMessage.localizedError(for: LLMError.unauthorized))
        XCTAssertNil(AIInferenceErrorMessage.localizedError(for: LLMError.server(statusCode: 502, message: "other service error")))
    }

    @MainActor
    func testProviderKeysAreIsolated() async throws {
        let (_, store, state) = fixture()
        try state.setMode(.byok)
        try state.saveKey("router-key")
        try state.addConnection(.openAI)
        XCTAssertFalse(state.hasStoredKey)
        XCTAssertThrowsError(try state.resolveSelection())
        try state.saveKey("openai-key")
        XCTAssertEqual(try state.resolveSelection().credentials?.configuration, .openAI)
        try state.removeKey()
        XCTAssertEqual(store.keys["openrouter"], "router-key")
        XCTAssertNil(store.keys[try XCTUnwrap(state.selectedProfileID)])
        try state.selectConnection("openrouter")
        XCTAssertTrue(state.hasStoredKey)
    }

    @MainActor
    func testConfigurationsPersistWithoutCredentials() async throws {
        let (defaults, store, state) = fixture()
        try state.setMode(.byok)
        try state.addConnection(.custom)
        var configuration = LLMCore.LLMBYOKConfiguration(
            baseURL: URL(string: "https://gateway.example.com/v1/")!,
            defaultModel: "logical-model",
            modelMapping: .init(aliases: ["logical-model": "team/actual-model"])
        )
        try state.saveConfiguration(configuration)
        try state.setModel("logical-model")
        configuration.defaultModel = nil
        try state.saveKey("synthetic-secret")
        let data = try XCTUnwrap(defaults.object(forKey: AIInferenceBillingState.profilesDefaultsKey) as? Data)
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("synthetic-secret"))
        let restored = AIInferenceBillingState(defaults: defaults, keyStore: store)
        XCTAssertEqual(restored.configuration, configuration)
        XCTAssertEqual(restored.selectedProfile?.provider, .custom)
        XCTAssertTrue(restored.hasStoredKey)
        XCTAssertEqual(try restored.resolveSelection().credentials?.configuration.defaultModel, "logical-model")
    }

    @MainActor
    func testChangedEndpointClearsItsKeyBeforeUse() async throws {
        let (_, store, state) = fixture()
        try state.saveKey("router-key")
        try state.setMode(.byok)
        try state.addConnection(.custom)
        var configuration = LLMCore.LLMBYOKConfiguration(baseURL: URL(string: "https://first.example.com/v1/")!)
        try state.saveConfiguration(configuration)
        try state.saveKey("first-endpoint-key")
        configuration.baseURL = URL(string: "https://second.example.com/v1/")!
        try state.saveConfiguration(configuration)
        XCTAssertFalse(state.hasStoredKey)
        XCTAssertThrowsError(try state.resolveSelection())
        XCTAssertNil(store.keys[try XCTUnwrap(state.selectedProfileID)])
        XCTAssertEqual(store.keys["openrouter"], "router-key")
    }

    @MainActor
    func testCorruptConfigurationCannotUsePresetOrPlatformBilling() async throws {
        let (defaults, store, _) = fixture()
        defaults.set("byok", forKey: AIInferenceBillingState.modeDefaultsKey)
        defaults.set(Data("invalid configuration".utf8), forKey: AIInferenceBillingState.profilesDefaultsKey)
        store.key = "synthetic-key"
        let restored = AIInferenceBillingState(defaults: defaults, keyStore: store)
        XCTAssertTrue(restored.usesBYOK)
        XCTAssertTrue(restored.configurationLoadFailed)
        XCTAssertNil(restored.configuration)
        XCTAssertThrowsError(try restored.resolveSelection())
    }

    @MainActor
    func testArbitraryModelIDsDoNotRequirePlatformCatalogEntries() async throws {
        let (_, _, state) = fixture()
        try state.setMode(.byok)
        try state.addConnection(.openAI)
        var configuration = LLMCore.LLMBYOKConfiguration.openAI
        try state.setModel("provider/unlisted-model")
        configuration.defaultModel = "provider/unlisted-model"
        try state.saveKey("synthetic-key")
        let model = try state.modelForChat()
        XCTAssertEqual(model.rawValue, "provider/unlisted-model")
        try await state.withSelectedBilling {
            let credentials = try await AIInferenceBilling.credentialsForRequest(for: model)
            XCTAssertEqual(credentials?.configuration, configuration)
        }
    }

    @MainActor
    func testConversationModelsAreIsolatedByProviderAndPersist() async throws {
        let (defaults, store, state) = fixture()
        try state.addConnection(.openAI)
        try state.setModel("custom/openai-model", for: "conversation")
        try state.addConnection(.anthropic)
        XCTAssertThrowsError(try state.modelForChat(conversationID: "conversation"))
        try state.setModel("custom/anthropic-model", for: "conversation")
        let restored = AIInferenceBillingState(defaults: defaults, keyStore: store)
        XCTAssertEqual(try restored.modelForChat(conversationID: "conversation").rawValue, "custom/anthropic-model")
        try restored.selectConnection(try XCTUnwrap(restored.profiles.first { $0.provider == .openAI }).id)
        XCTAssertEqual(try restored.modelForChat(conversationID: "conversation").rawValue, "custom/openai-model")
        restored.forgetConversation("conversation")
        XCTAssertNil(restored.conversationModels[try XCTUnwrap(restored.selectedProfileID)]?["conversation"])
        XCTAssertEqual(try restored.modelForChat().rawValue, "custom/openai-model")
    }

    @MainActor
    func testInvalidModelIDsCannotReplaceTheSelectedModel() async throws {
        let (_, _, state) = fixture()
        try state.setModel("valid/model", for: "conversation")
        for invalid in ["", "model name", "model\nname", "模型", String(repeating: "x", count: 513)] {
            XCTAssertThrowsError(try state.setModel(invalid, for: "conversation"))
            XCTAssertEqual(try state.modelForChat(conversationID: "conversation").rawValue, "valid/model")
        }
    }

    @MainActor
    func testAuxiliaryRequestsFollowBYOKModelsWithoutPlatformFallback() async throws {
        let (_, _, state) = fixture()
        try state.setMode(.byok)
        try state.addConnection(.custom)
        var configuration = LLMCore.LLMBYOKConfiguration(
            baseURL: URL(string: "https://gateway.example.com/v1/")!,
            defaultModel: "default-model"
        )
        try state.saveConfiguration(configuration)
        try state.saveKey("synthetic-key")
        try state.setModel("default-model")
        XCTAssertEqual(try state.modelForAuxiliaryRequest(fallback: .gpt4oMini).rawValue, "default-model")
        XCTAssertEqual(try state.modelForAuxiliaryRequest(fallback: .gpt4oMini, conversationModel: .other("chat-model")).rawValue, "chat-model")
        configuration.options.auxiliaryModel = "utility-model"
        try state.saveConfiguration(configuration)
        XCTAssertEqual(try state.modelForAuxiliaryRequest(fallback: .gpt4oMini, conversationModel: .other("chat-model")).rawValue, "chat-model")
    }

    @MainActor
    func testIncompatibleAuxiliaryDefaultsMustBeConfigured() async throws {
        let (_, _, state) = fixture()
        try state.setMode(.byok)
        try state.addConnection(.anthropic)
        try state.saveKey("synthetic-key")
        XCTAssertThrowsError(try state.modelForAuxiliaryRequest(fallback: .gpt4oMini))
    }

    @MainActor
    func testLegacyOpenRouterSelectionStillUsesItsOwnKey() async throws {
        let (defaults, store, _) = fixture()
        defaults.set("openRouter", forKey: AIInferenceBillingState.modeDefaultsKey)
        store.key = "synthetic-key"
        let restored = AIInferenceBillingState(defaults: defaults, keyStore: store)
        XCTAssertTrue(restored.usesBYOK)
        var expectedConfiguration = LLMBYOKConfiguration.openRouter
        expectedConfiguration.options.auxiliaryModel = nil
        XCTAssertEqual(try restored.resolveSelection().credentials?.configuration, expectedConfiguration)
    }

    @MainActor
    func testModelDiscoveryWorksBeforeChoosingAModelAndCachesMetadata() async throws {
        let (_, _, state) = fixture()
        try state.setMode(.byok)
        try state.addConnection(.openAI)
        try state.saveKey("synthetic-key")
        XCTAssertNil(state.configuration?.defaultModel)
        let fetcher = ModelCatalogFetchStub()
        let catalog = AIInferenceModelCatalog { provider, _ in try await fetcher.fetch(provider) }
        await catalog.load(for: state, force: true)
        XCTAssertEqual(catalog.snapshot(for: state).models.map(\.id), ["first-model", "second-model"])
        XCTAssertEqual(catalog.displayName(for: "first-model", billing: state), "Alpha")
        await catalog.load(for: state)
        let count = await fetcher.count
        XCTAssertEqual(count, 1)
        try state.setModel("other-model")
        await catalog.load(for: state)
        let afterModelChange = await fetcher.count
        XCTAssertEqual(afterModelChange, 1, "Selecting a model must not fetch the provider catalog again")
    }

    @MainActor
    func testChangingKeyInvalidatesTheVisibleModelCatalog() async throws {
        let (_, _, state) = fixture()
        try state.setMode(.byok)
        try state.saveKey("first-synthetic-key")
        let fetcher = ModelCatalogFetchStub()
        let catalog = AIInferenceModelCatalog { provider, _ in try await fetcher.fetch(provider) }
        await catalog.load(for: state, force: true)
        XCTAssertFalse(catalog.snapshot(for: state).models.isEmpty)
        try state.saveKey("second-synthetic-key")
        XCTAssertTrue(catalog.snapshot(for: state).models.isEmpty)
        await catalog.load(for: state, force: true)
        let count = await fetcher.count
        XCTAssertEqual(count, 2)
    }

    @MainActor
    func testLateModelListCannotReplaceTheNewProvidersModels() async throws {
        let (_, _, state) = fixture()
        try state.setMode(.byok)
        try state.saveKey("router-synthetic-key")
        let fetcher = ModelCatalogFetchStub(suspended: true)
        let catalog = AIInferenceModelCatalog { provider, _ in try await fetcher.fetch(provider) }
        let first = Task { await catalog.load(for: state, force: true) }
        await fetcher.waitForRequests(1)
        try state.addConnection(.openAI)
        try state.saveKey("openai-synthetic-key")
        let second = Task { await catalog.load(for: state, force: true) }
        await fetcher.waitForRequests(2)
        await fetcher.complete(1, models: [.init(id: "new-provider-model")])
        await second.value
        await fetcher.complete(0, models: [.init(id: "old-provider-model")])
        await first.value
        XCTAssertEqual(catalog.snapshot(for: state).models.map(\.id), ["new-provider-model"])
    }

    @MainActor
    func testDisabledDiscoveryAndPlatformModeNeverFetchAList() async throws {
        let (_, _, state) = fixture()
        try state.setMode(.byok)
        try state.saveKey("synthetic-key")
        var configuration = try XCTUnwrap(state.configuration)
        configuration.modelDiscovery = nil
        try state.saveConfiguration(configuration)
        let fetcher = ModelCatalogFetchStub()
        let catalog = AIInferenceModelCatalog { provider, _ in try await fetcher.fetch(provider) }
        await catalog.load(for: state, force: true)
        XCTAssertNil(catalog.snapshot(for: state).errorMessage)
        XCTAssertEqual(try state.modelForChat(overridingModelID: "manual-model").rawValue, "manual-model")
        try state.setMode(.platform)
        XCTAssertThrowsError(try state.modelDiscoveryProvider())
        await catalog.load(for: state, force: true)
        let count = await fetcher.count
        XCTAssertEqual(count, 0)
        XCTAssertTrue(catalog.snapshot(for: state).models.isEmpty)
    }

    @MainActor
    func testSameProviderConnectionsIsolateKeysModelsAndSelection() async throws {
        let defaults = MemoryDefaults()
        let keys = MemoryKeyStore()
        let state = AIInferenceBillingState(defaults: defaults, keyStore: keys)
        XCTAssertTrue(state.profiles.isEmpty)
        try state.setMode(.byok)
        XCTAssertThrowsError(try state.resolveSelection())
        let first = try state.addConnection(.openAI)
        try state.saveKey("first-synthetic-key")
        try state.setModel("first-model", for: "conversation")
        let second = try state.addConnection(.openAI)
        XCTAssertNotEqual(first.id, second.id)
        XCTAssertFalse(state.hasStoredKey)
        XCTAssertNil(state.modelID(for: "conversation"))
        try state.saveKey("second-synthetic-key")
        try state.setModel("second-model", for: "conversation")
        let restored = AIInferenceBillingState(defaults: defaults, keyStore: keys)
        XCTAssertEqual(restored.profiles.count, 2)
        XCTAssertEqual(restored.selectedProfileID, second.id)
        XCTAssertEqual(try restored.keyForEditing(), "second-synthetic-key")
        try restored.selectConnection(first.id)
        XCTAssertEqual(try restored.keyForEditing(), "first-synthetic-key")
        XCTAssertEqual(restored.modelID(for: "conversation"), "first-model")
        try restored.removeConnection(first.id)
        XCTAssertNil(restored.selectedProfileID)
        XCTAssertNil(keys.keys[first.id])
        XCTAssertEqual(keys.keys[second.id], "second-synthetic-key")
        XCTAssertTrue(restored.usesBYOK)
        XCTAssertThrowsError(try restored.resolveSelection())
        XCTAssertFalse(String(describing: defaults.values).contains("synthetic-key"))
    }

    @MainActor
    func testEditingInactiveConnectionDoesNotChangeSelectedCredentials() async throws {
        let (_, _, state) = fixture()
        try state.setMode(.byok)
        let first = try state.addConnection(.openAI)
        try state.saveKey("first-synthetic-key")
        try state.setModel("first-model")
        let second = try state.addConnection(.openAI)
        try state.saveKey("second-synthetic-key")
        var config = try XCTUnwrap(first.configuration)
        config.baseURL = URL(string: "https://gateway.example.com/v1/")!
        try state.updateConnection(first.id, name: "Work", configuration: config, apiKey: "updated-first-key")
        XCTAssertEqual(state.selectedProfileID, second.id)
        XCTAssertEqual(try state.keyForEditing(), "second-synthetic-key")
        XCTAssertEqual(try state.keyForEditing(profileID: first.id), "updated-first-key")
        try state.selectConnection(first.id)
        XCTAssertEqual(state.selectedProfile?.displayName, "Work")
        XCTAssertNil(state.modelID(for: nil))
        XCTAssertNotNil(try state.resolveSelection().credentials)
    }

    @MainActor
    func testAddingConfiguredConnectionStoresKeyBeforePublishing() async throws {
        let (defaults, keys, state) = fixture()
        let count = state.profiles.count
        let selectedID = state.selectedProfileID
        let savedPreferences = try XCTUnwrap(defaults.object(forKey: AIInferenceBillingState.profilesDefaultsKey) as? Data)
        keys.writeFailure = FixtureError.failed
        XCTAssertThrowsError(try state.addConnection(
            .openAI, name: "Work", configuration: .openAI, apiKey: "synthetic-new-key"
        ))
        XCTAssertEqual(state.profiles.count, count)
        XCTAssertEqual(state.selectedProfileID, selectedID)
        XCTAssertEqual(defaults.object(forKey: AIInferenceBillingState.profilesDefaultsKey) as? Data, savedPreferences)
        XCTAssertTrue(keys.keys.isEmpty)

        keys.writeFailure = nil
        let profile = try state.addConnection(.openAI, name: "Work", configuration: .openAI, apiKey: "synthetic-new-key")
        XCTAssertEqual(state.profiles.count, count + 1)
        XCTAssertEqual(state.selectedProfileID, profile.id)
        XCTAssertEqual(profile.displayName, "Work")
        XCTAssertEqual(try state.keyForEditing(), "synthetic-new-key")
        XCTAssertFalse(String(describing: defaults.values).contains("synthetic-new-key"))
    }

    @MainActor
    func testFailedConnectionEditPreservesSavedSettingsAndCredentials() async throws {
        let (defaults, keys, state) = fixture()
        try state.setMode(.byok)
        let connection = try state.addConnection(.openAI, name: "Personal", configuration: .openAI, apiKey: "original-key")
        try state.setModel("chat-model", for: "conversation")
        let savedData = defaults.object(forKey: AIInferenceBillingState.profilesDefaultsKey) as? Data
        var configuration = LLMCore.LLMBYOKConfiguration.openAI
        configuration.baseURL = URL(string: "https://gateway.example.com/v1/")!
        keys.writeFailure = FixtureError.failed
        XCTAssertThrowsError(try state.updateConnection(connection.id, name: "Work", configuration: configuration, apiKey: "replacement-key"))
        XCTAssertEqual(state.selectedProfile?.displayName, "Personal")
        XCTAssertEqual(state.configuration, .openAI)
        XCTAssertEqual(try state.keyForEditing(), "original-key")
        XCTAssertEqual(state.modelID(for: "conversation"), "chat-model")
        XCTAssertEqual(defaults.object(forKey: AIInferenceBillingState.profilesDefaultsKey) as? Data, savedData)

        keys.writeFailure = nil
        try state.updateConnection(connection.id, name: "Work", configuration: configuration, apiKey: "replacement-key")
        XCTAssertEqual(state.profiles.count, 2)
        XCTAssertEqual(state.selectedProfileID, connection.id)
        XCTAssertEqual(state.selectedProfile?.displayName, "Work")
        XCTAssertEqual(state.configuration, configuration)
        XCTAssertEqual(try state.keyForEditing(), "replacement-key")
        XCTAssertNil(state.modelID(for: "conversation"))
    }

    @MainActor
    private func fixture() -> (MemoryDefaults, MemoryKeyStore, AIInferenceBillingState) {
        let defaults = MemoryDefaults()
        let store = MemoryKeyStore()
        defaults.set("openrouter", forKey: AIInferenceBillingState.connectionDefaultsKey)
        return (defaults, store, AIInferenceBillingState(defaults: defaults, keyStore: store))
    }
}

final class AIServiceConsentTests: XCTestCase {
    @MainActor
    func testEachServiceRequiresItsOwnPersistentConsent() async throws {
        let defaults = MemoryDefaults()
        let consent = AIServiceConsentState(defaults: defaults)
        XCTAssertFalse(consent.hasAccepted(.platform))
        XCTAssertFalse(consent.hasAccepted(.byok))
        XCTAssertTrue(defaults.values.isEmpty)
        consent.accept(.platform)
        XCTAssertTrue(consent.hasAccepted(.platform))
        XCTAssertFalse(consent.hasAccepted(.byok))

        let restored = AIServiceConsentState(defaults: defaults)
        XCTAssertTrue(restored.hasAccepted(.platform))
        XCTAssertFalse(restored.hasAccepted(.byok))
        restored.accept(.byok)
        defaults.set(false, forKey: AIChatPreferences.isAIEnabledDefaultsKey)
        let disabled = AIServiceConsentState(defaults: defaults)
        XCTAssertTrue(disabled.hasAccepted(.platform))
        XCTAssertTrue(disabled.hasAccepted(.byok))
    }

    @MainActor
    func testLegacyPlatformPermissionDoesNotAuthorizeBYOK() async throws {
        let defaults = MemoryDefaults()
        defaults.set(true, forKey: AIChatPreferences.isAIEnabledDefaultsKey)
        let consent = AIServiceConsentState(defaults: defaults)
        XCTAssertTrue(consent.hasAcceptedSelectedMode)
        XCTAssertTrue(consent.hasAccepted(.platform))
        XCTAssertFalse(consent.hasAccepted(.byok))
        defaults.set("byok", forKey: AIInferenceBillingState.modeDefaultsKey)
        XCTAssertFalse(consent.hasAcceptedSelectedMode)
    }

    @MainActor
    func testLegacyBYOKEnableFlagDoesNotGrantEitherPermission() async throws {
        for mode in ["byok", "openRouter"] {
            let defaults = MemoryDefaults()
            defaults.set(true, forKey: AIChatPreferences.isAIEnabledDefaultsKey)
            defaults.set(mode, forKey: AIInferenceBillingState.modeDefaultsKey)
            let consent = AIServiceConsentState(defaults: defaults)
            XCTAssertFalse(consent.hasAcceptedSelectedMode)
            XCTAssertFalse(consent.hasAccepted(.platform))
            XCTAssertFalse(consent.hasAccepted(.byok))
            consent.accept(.byok)
            XCTAssertTrue(consent.hasAcceptedSelectedMode)
            XCTAssertFalse(consent.hasAccepted(.platform))
        }
    }

    @MainActor
    func testOutdatedConsentAndUnknownModesAreNotAccepted() async throws {
        let defaults = MemoryDefaults()
        defaults.set(true, forKey: AIChatPreferences.isAIEnabledDefaultsKey)
        defaults.set(["platform": 0, "byok": 1], forKey: AIServiceConsentState.defaultsKey)
        let consent = AIServiceConsentState(defaults: defaults)
        XCTAssertFalse(consent.hasAcceptedSelectedMode)
        XCTAssertFalse(consent.hasAccepted(.platform))
        XCTAssertTrue(consent.hasAccepted(.byok))
        defaults.set("unknown", forKey: AIInferenceBillingState.modeDefaultsKey)
        XCTAssertFalse(consent.hasAcceptedSelectedMode)
    }
}

private enum FixtureError: Error {
    case failed
}

private final class MemoryKeyStore: AIInferenceKeyStoring {
    var keys: [String: String] = [:]
    var key: String? {
        get { keys["openrouter"] }
        set { keys["openrouter"] = newValue }
    }
    var readFailure: Error?
    var writeFailure: Error?
    var readCount = 0

    func readKey(for account: String) throws -> String? {
        readCount += 1
        if let readFailure { throw readFailure }
        return keys[account]
    }

    func saveKey(_ key: String, for account: String) throws {
        if let writeFailure { throw writeFailure }
        keys[account] = key
    }
    func removeKey(for account: String) throws { keys[account] = nil }
}

/// No test preference writes reach the device's actual defaults or Keychain.
private final class MemoryDefaults: UserDefaults {
    var values: [String: Any] = [:]
    override func object(forKey defaultName: String) -> Any? { values[defaultName] }
    override func string(forKey defaultName: String) -> String? { values[defaultName] as? String }
    override func dictionary(forKey defaultName: String) -> [String: Any]? { values[defaultName] as? [String: Any] }
    override func set(_ value: Any?, forKey defaultName: String) { values[defaultName] = value }
}

private actor ModelCatalogFetchStub {
    let suspended: Bool
    private var configurations: [LLMCore.LLMBYOKConfiguration] = []
    private var pending: [Int: CheckedContinuation<[LLMBYOKModel], Error>] = [:]
    private var waiters: [(Int, CheckedContinuation<Void, Never>)] = []

    init(suspended: Bool = false) { self.suspended = suspended }
    var count: Int { configurations.count }

    func fetch(_ provider: LLMBYOKProvider) async throws -> [LLMBYOKModel] {
        let index = configurations.count
        configurations.append(provider.configuration)
        if suspended {
            return try await withCheckedThrowingContinuation { continuation in
                pending[index] = continuation
                notifyWaiters()
            }
        }
        notifyWaiters()
        return [
            .init(id: "second-model", name: "Zulu"),
            .init(id: "first-model", name: "Alpha"),
            .init(id: "first-model", name: "Duplicate"),
        ]
    }

    func waitForRequests(_ count: Int) async {
        guard configurations.count < count else { return }
        await withCheckedContinuation { waiters.append((count, $0)) }
    }

    func complete(_ index: Int, models: [LLMBYOKModel]) {
        pending.removeValue(forKey: index)?.resume(returning: models)
    }

    private func notifyWaiters() {
        let ready = waiters.filter { $0.0 <= configurations.count }
        waiters.removeAll { $0.0 <= configurations.count }
        for (_, continuation) in ready { continuation.resume() }
    }
}
