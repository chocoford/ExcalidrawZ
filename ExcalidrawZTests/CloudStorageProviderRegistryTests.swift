//
//  CloudStorageProviderRegistryTests.swift
//  ExcalidrawZTests
//

import XCTest
@testable import ExcalidrawZ

final class CloudStorageProviderRegistryTests: XCTestCase {
    func testRegistersAndReturnsProvider() async throws {
        let registry = CloudStorageProviderRegistry()
        let provider = StubCloudStorageProvider(
            id: .microsoftOneDrive,
            displayName: "OneDrive"
        )

        try await registry.register(provider)

        let registered = try await registry.provider(withID: .microsoftOneDrive)
        XCTAssertEqual(registered.descriptor, provider.descriptor)
    }

    func testRejectsDuplicateProviderID() async throws {
        let registry = CloudStorageProviderRegistry()
        let first = StubCloudStorageProvider(id: .googleDrive, displayName: "Google Drive")
        let duplicate = StubCloudStorageProvider(id: .googleDrive, displayName: "Duplicate")

        try await registry.register(first)

        do {
            try await registry.register(duplicate)
            XCTFail("Expected duplicate registration to fail")
        } catch {
            XCTAssertEqual(
                error as? CloudStorageProviderRegistry.RegistryError,
                .providerAlreadyRegistered(.googleDrive)
            )
        }
    }

    func testReturnsSortedDescriptors() async throws {
        let registry = CloudStorageProviderRegistry()
        try await registry.register(
            StubCloudStorageProvider(id: .microsoftOneDrive, displayName: "OneDrive")
        )
        try await registry.register(
            StubCloudStorageProvider(id: .dropbox, displayName: "Dropbox")
        )

        let descriptors = await registry.registeredProviderDescriptors()
        let names = descriptors.map(\.displayName)
        XCTAssertEqual(names, ["Dropbox", "OneDrive"])
    }
}

private struct StubCloudStorageProvider: CloudStorageProvider {
    let descriptor: CloudStorageProviderDescriptor

    init(id: CloudStorageProviderID, displayName: String) {
        descriptor = CloudStorageProviderDescriptor(
            id: id,
            displayName: displayName,
            capabilities: .readWrite
        )
    }

    func authorizationStatus() async -> CloudStorageAuthorizationStatus {
        .signedOut
    }

    func authorize() async throws -> CloudStorageAccount {
        throw CloudStorageError.unsupportedOperation(.authorize)
    }

    func makeSession(for account: CloudStorageAccount) async throws -> any CloudStorageSession {
        throw CloudStorageError.accountUnavailable(account.id)
    }

    func signOut(accountID: CloudStorageAccountID) async throws {}
}
