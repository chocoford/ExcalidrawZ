import XCTest
@testable import ExcalidrawZ

@MainActor
final class GoogleDriveAdditionalAccessTests: XCTestCase {
    func testSupplementalPickerCanSelectFilesAndFoldersOutsideTheOriginalRootFilter() async {
        let items = GoogleDrivePickerMode.additionalItems.queryItems(folderIDHint: "linked-root")
        let values = Dictionary(uniqueKeysWithValues: items.compactMap { item in
            item.value.map { (item.name, $0) }
        })

        XCTAssertEqual(values["trigger_onepick"], "true")
        XCTAssertEqual(values["allow_folder_selection"], "true")
        XCTAssertEqual(values["allow_multiple"], "true")
        XCTAssertNil(values["mimetypes"])
        XCTAssertNil(values["file_ids"])
        XCTAssertTrue(GoogleDrivePickerMode.additionalItems.requiresSelection)
    }

    func testOriginalRootReauthorizationStillSelectsOneSpecificFolder() async {
        let items = GoogleDrivePickerMode.folder.queryItems(folderIDHint: "linked-root")
        let values = Dictionary(uniqueKeysWithValues: items.compactMap { item in
            item.value.map { (item.name, $0) }
        })

        XCTAssertEqual(values["allow_multiple"], "false")
        XCTAssertEqual(values["mimetypes"], GoogleDriveFile.folderMIMEType)
        XCTAssertEqual(values["file_ids"], "linked-root")
        XCTAssertTrue(GoogleDrivePickerMode.none.queryItems().isEmpty)
        XCTAssertFalse(GoogleDrivePickerMode.none.requiresSelection)
    }

    func testAdditionalAccessPreservesTheLinkedRootAndAccount() async throws {
        let fixture = try await makeFixture()
        defer { fixture.cleanup() }
        let locations = fixture.store.locations

        try await fixture.store.authorizeAdditionalGoogleDriveItems(in: fixture.location)

        XCTAssertEqual(fixture.store.locations, locations)
        XCTAssertEqual(fixture.store.accounts(for: .googleDrive), [fixture.authenticator.account])
        XCTAssertEqual(fixture.authenticator.additionalAuthorizationCount, 1)
        XCTAssertTrue(fixture.store.connectingProviderIDs.isEmpty)
    }

    func testCancellingDoesNotRemoveTheLocationOrLeaveAuthorizationBusy() async throws {
        let fixture = try await makeFixture()
        defer { fixture.cleanup() }
        fixture.authenticator.authorizeAdditional = { _ in
            throw CloudStorageError.authorizationCancelled
        }

        do {
            try await fixture.store.authorizeAdditionalGoogleDriveItems(in: fixture.location)
            XCTFail("Expected cancellation")
        } catch {
            XCTAssertEqual(error as? CloudStorageError, .authorizationCancelled)
        }

        XCTAssertEqual(fixture.store.locations, [fixture.location])
        XCTAssertTrue(fixture.store.connectingProviderIDs.isEmpty)
    }

    func testSelectingADifferentAccountDoesNotReplaceTheLinkedAccount() async throws {
        let fixture = try await makeFixture()
        defer { fixture.cleanup() }
        fixture.authenticator.authorizeAdditional = { _ in
            CloudStorageAccount(
                providerID: .googleDrive,
                id: .init(rawValue: "other-account"),
                displayName: "Other account",
                emailAddress: nil
            )
        }

        do {
            try await fixture.store.authorizeAdditionalGoogleDriveItems(in: fixture.location)
            XCTFail("A grant for another account must be rejected")
        } catch {
            guard let cloudError = error as? CloudStorageError,
                  case .invalidProviderResponse = cloudError else {
                return XCTFail("Unexpected error: \(error)")
            }
        }

        XCTAssertEqual(fixture.store.locations, [fixture.location])
        XCTAssertEqual(fixture.store.accounts(for: .googleDrive), [fixture.authenticator.account])
        XCTAssertTrue(fixture.store.connectingProviderIDs.isEmpty)
    }

    func testDuplicateRequestDoesNotOpenAnotherPickerOrRestoreARemovedLocation() async throws {
        let fixture = try await makeFixture()
        defer { fixture.cleanup() }
        let opened = expectation(description: "Picker opened")
        var continuation: CheckedContinuation<CloudStorageAccount, Error>?
        fixture.authenticator.authorizeAdditional = { _ in
            try await withCheckedThrowingContinuation {
                continuation = $0
                opened.fulfill()
            }
        }
        let firstRequest = Task {
            try await fixture.store.authorizeAdditionalGoogleDriveItems(in: fixture.location)
        }
        await fulfillment(of: [opened], timeout: 2)

        do {
            try await fixture.store.authorizeAdditionalGoogleDriveItems(in: fixture.location)
            XCTFail("Expected the duplicate request to be ignored")
        } catch {
            XCTAssertEqual(error as? CloudStorageError, .authorizationCancelled)
        }
        XCTAssertEqual(fixture.authenticator.additionalAuthorizationCount, 1)

        fixture.store.removeLocation(fixture.location)
        continuation?.resume(returning: fixture.authenticator.account)
        do {
            try await firstRequest.value
            XCTFail("A removed location must remain removed")
        } catch {
            XCTAssertEqual(error as? CloudStorageError, .authorizationCancelled)
        }
        XCTAssertTrue(fixture.store.locations.isEmpty)
        XCTAssertTrue(fixture.store.connectingProviderIDs.isEmpty)
    }

    private func makeFixture() async throws -> Fixture {
        let registry = CloudStorageProviderRegistry()
        let authenticator = AdditionalAccessAuthenticator()
        try await registry.register(GoogleDriveCloudStorageProvider(
            authenticator: authenticator,
            configuration: GoogleDriveConfiguration(clientID: "test.apps.googleusercontent.com")
        ))
        let suite = "GoogleDriveAdditionalAccessTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let store = CloudStorageConnectionStore(registry: registry, userDefaults: defaults)
        await store.refresh()
        let root = CloudStorageItem(
            id: .init(rawValue: "linked-root"),
            parentID: nil,
            name: "Drawings",
            kind: .folder,
            contentType: nil,
            size: nil,
            createdAt: nil,
            modifiedAt: nil,
            remoteURL: nil,
            revision: nil
        )
        store.saveLocation(providerID: .googleDrive, account: authenticator.account, folder: root)
        return Fixture(
            store: store,
            authenticator: authenticator,
            location: try XCTUnwrap(store.locations.first),
            cleanup: { defaults.removePersistentDomain(forName: suite) }
        )
    }

    private struct Fixture {
        let store: CloudStorageConnectionStore
        let authenticator: AdditionalAccessAuthenticator
        let location: CloudStorageLocation
        let cleanup: () -> Void
    }
}

@MainActor
private final class AdditionalAccessAuthenticator: GoogleDriveAuthenticating {
    let account = CloudStorageAccount(
        providerID: .googleDrive,
        id: .init(rawValue: "linked-account"),
        displayName: "Linked account",
        emailAddress: "test@example.com"
    )
    var additionalAuthorizationCount = 0
    var authorizeAdditional: ((CloudStorageAccount) async throws -> CloudStorageAccount)?

    func accounts() async throws -> [CloudStorageAccount] { [account] }
    func authorize() async throws -> CloudStorageAccount { account }
    func accessToken(for accountID: CloudStorageAccountID) async throws -> String { "test-token" }
    func signOut(accountID: CloudStorageAccountID) async throws {}

    func authorizeAndSelectFolder(
        accountHint: CloudStorageAccount?,
        folderIDHint: CloudStorageItemID?
    ) async throws -> GoogleDriveFolderAuthorization {
        XCTFail("Supplemental access must not replace the linked root")
        throw CloudStorageError.authorizationCancelled
    }

    func authorizeAdditionalItems(for account: CloudStorageAccount) async throws -> CloudStorageAccount {
        additionalAuthorizationCount += 1
        if let authorizeAdditional { return try await authorizeAdditional(account) }
        return self.account
    }
}
