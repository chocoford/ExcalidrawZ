//
//  CloudStorageProviderRegistry.swift
//  ExcalidrawZ
//

import Foundation

actor CloudStorageProviderRegistry {
    static let shared = CloudStorageProviderRegistry()

    private var providers: [CloudStorageProviderID: any CloudStorageProvider] = [:]

    func register(_ provider: any CloudStorageProvider) throws {
        let providerID = provider.descriptor.id
        guard providers[providerID] == nil else {
            throw RegistryError.providerAlreadyRegistered(providerID)
        }
        providers[providerID] = provider
    }

    func unregisterProvider(withID providerID: CloudStorageProviderID) {
        providers.removeValue(forKey: providerID)
    }

    func provider(withID providerID: CloudStorageProviderID) throws -> any CloudStorageProvider {
        guard let provider = providers[providerID] else {
            throw RegistryError.providerNotRegistered(providerID)
        }
        return provider
    }

    func registeredProviderDescriptors() -> [CloudStorageProviderDescriptor] {
        providers.values
            .map(\.descriptor)
            .sorted {
                $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
            }
    }
}

extension CloudStorageProviderRegistry {
    enum RegistryError: LocalizedError, Equatable {
        case providerAlreadyRegistered(CloudStorageProviderID)
        case providerNotRegistered(CloudStorageProviderID)

        var errorDescription: String? {
            switch self {
                case .providerAlreadyRegistered(let providerID):
                    return "Cloud storage provider is already registered: \(providerID.rawValue)"
                case .providerNotRegistered(let providerID):
                    return "Cloud storage provider is not registered: \(providerID.rawValue)"
            }
        }
    }
}
