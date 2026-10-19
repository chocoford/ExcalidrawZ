import XCTest
@testable import ExcalidrawZ

final class ICloudContainerConfigurationTests: XCTestCase {
    func testCloudKitUsesConfiguredContainer() {
        let configuration = ICloudContainerConfiguration(infoDictionary: [
            "ExcalidrawZICloudContainerIdentifier": "iCloud.example.separate-test"
        ])

        XCTAssertEqual(
            configuration.cloudKitContainerOptions?.containerIdentifier,
            "iCloud.example.separate-test"
        )
    }

    func testICloudDriveUsesTheSameConfiguredContainer() {
        let configuration = ICloudContainerConfiguration(infoDictionary: [
            "ExcalidrawZICloudContainerIdentifier": "iCloud.example.separate-test"
        ])
        let expectedURL = URL(fileURLWithPath: "/isolated-test-container")
        var requestedIdentifier: String?

        let url = configuration.ubiquityContainerURL { identifier in
            requestedIdentifier = identifier
            return expectedURL
        }

        XCTAssertEqual(requestedIdentifier, configuration.cloudKitContainerOptions?.containerIdentifier)
        XCTAssertEqual(requestedIdentifier, "iCloud.example.separate-test")
        XCTAssertEqual(url, expectedURL)
    }

    func testInvalidConfigurationDoesNotAccessAnyContainer() {
        let invalidValues: [Any] = [
            "", "$(ICLOUD_CONTAINER)", "iCloud.$(NAME)", "iCloud.",
            " iCloud.example.test", "iCloud.example.test\n", "example.test", 42,
            "iCloud.example/test", "iCloud.example:container", "iCloud..",
            "iCloud.example.*", "iCloud.example..test"
        ]

        for value in invalidValues {
            let configuration = ICloudContainerConfiguration(infoDictionary: [
                "ExcalidrawZICloudContainerIdentifier": value
            ])
            var didResolve = false

            let url = configuration.ubiquityContainerURL { _ in
                didResolve = true
                return URL(fileURLWithPath: "/unexpected-container")
            }

            XCTAssertNil(configuration.identifier, "Invalid value: \(value)")
            XCTAssertNil(configuration.cloudKitContainerOptions, "Invalid value: \(value)")
            XCTAssertNil(url)
            XCTAssertFalse(didResolve)
        }
    }

    func testMissingConfigurationDoesNotSelectProductionContainer() {
        let configuration = ICloudContainerConfiguration(infoDictionary: [:])

        XCTAssertNil(configuration.identifier)
        XCTAssertNil(configuration.cloudKitContainerOptions)
        XCTAssertNil(configuration.ubiquityContainerURL { _ in
            XCTFail("Missing configuration must not perform a container lookup")
            return nil
        })
    }

    func testUnavailableConfiguredContainerDoesNotTryAnotherContainer() {
        let configuration = ICloudContainerConfiguration(infoDictionary: [
            "ExcalidrawZICloudContainerIdentifier": "iCloud.example.separate-test"
        ])
        var requestedIdentifiers: [String] = []

        let url = configuration.ubiquityContainerURL { identifier in
            requestedIdentifiers.append(identifier)
            return nil
        }

        XCTAssertNil(url)
        XCTAssertEqual(requestedIdentifiers, ["iCloud.example.separate-test"])
    }
}
