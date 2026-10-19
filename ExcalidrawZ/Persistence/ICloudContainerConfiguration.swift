import Foundation
import CoreData

/// Uses the same build setting as the cloud entitlements. Invalid configuration
/// disables cloud access instead of selecting another app's container.
struct ICloudContainerConfiguration {
    static let current = ICloudContainerConfiguration(
        infoDictionary: Bundle.main.infoDictionary ?? [:]
    )

    let identifier: String?

    init(infoDictionary: [String: Any]) {
        guard let value = infoDictionary["ExcalidrawZICloudContainerIdentifier"] as? String,
              value.range(
                of: #"\AiCloud\.[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)*\z"#,
                options: .regularExpression
              ) != nil else {
            identifier = nil
            return
        }
        identifier = value
    }

    var cloudKitContainerOptions: NSPersistentCloudKitContainerOptions? {
        identifier.map { NSPersistentCloudKitContainerOptions(containerIdentifier: $0) }
    }

    func ubiquityContainerURL(
        resolve: (String) -> URL? = {
            FileManager.default.url(forUbiquityContainerIdentifier: $0)
        }
    ) -> URL? {
        guard let identifier else { return nil }
        return resolve(identifier)
    }
}
