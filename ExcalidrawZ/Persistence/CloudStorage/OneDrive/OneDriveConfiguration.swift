//
//  OneDriveConfiguration.swift
//  ExcalidrawZ
//

import Foundation

struct OneDriveConfiguration: Sendable {
    static let graphScopes = ["Files.ReadWrite"]

    let clientID: String
    let authorityURL: URL
    let redirectURI: String
    let scopes: [String]

    init(
        clientID: String,
        bundleIdentifier: String,
        authorityURL: URL = URL(string: "https://login.microsoftonline.com/common")!,
        scopes: [String] = Self.graphScopes
    ) {
        self.clientID = clientID
        self.authorityURL = authorityURL
        self.redirectURI = "msauth.\(bundleIdentifier)://auth"
        self.scopes = scopes
    }
}
