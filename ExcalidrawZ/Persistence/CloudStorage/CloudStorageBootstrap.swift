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
        await registerOneDrive()
        await registerDropbox()
    }

    @MainActor
    private static func registerOneDrive() async {
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

    @MainActor
    private static func registerDropbox() async {
        guard let appKey = DropboxConfiguration.appKey(in: .main) else {
            logger.debug("Dropbox provider is not configured")
            return
        }

        let configuration = DropboxConfiguration(appKey: appKey)
        let authenticator = DropboxOAuthAuthenticator(configuration: configuration)
        do {
            try await CloudStorageProviderRegistry.shared.register(
                DropboxCloudStorageProvider(
                    authenticator: authenticator,
                    configuration: configuration
                )
            )
            logger.info("Registered Dropbox cloud storage provider")
        } catch CloudStorageProviderRegistry.RegistryError.providerAlreadyRegistered(_) {
            return
        } catch {
            logger.error("Failed to register Dropbox cloud storage provider: \(error)")
        }
    }

}
