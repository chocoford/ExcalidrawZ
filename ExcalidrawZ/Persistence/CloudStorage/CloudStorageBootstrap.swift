//
//  CloudStorageBootstrap.swift
//  ExcalidrawZ
//

import Foundation
import Logging

enum CloudStorageBootstrap {
    private static let logger = Logger(label: "CloudStorageBootstrap")

    @MainActor
    static func registerConfiguredProviders() async {
        guard let clientID = Secrets.shared.oneDriveClientID,
              let bundleIdentifier = Bundle.main.bundleIdentifier else {
            logger.debug("OneDrive provider is not configured")
            return
        }

        do {
            let configuration = OneDriveConfiguration(
                clientID: clientID,
                bundleIdentifier: bundleIdentifier
            )
            let authenticator = try OneDriveMSALAuthenticator(configuration: configuration)
            try await CloudStorageProviderRegistry.shared.register(
                OneDriveCloudStorageProvider(authenticator: authenticator)
            )
            logger.info("Registered OneDrive cloud storage provider")
        } catch CloudStorageProviderRegistry.RegistryError.providerAlreadyRegistered(_) {
            return
        } catch {
            logger.error("Failed to register OneDrive cloud storage provider: \(error)")
        }
    }
}
