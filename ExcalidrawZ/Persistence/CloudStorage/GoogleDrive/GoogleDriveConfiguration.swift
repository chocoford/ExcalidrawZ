//
//  GoogleDriveConfiguration.swift
//  ExcalidrawZ
//

import Foundation

struct GoogleDriveConfiguration: Sendable {
    static let driveScope = "https://www.googleapis.com/auth/drive.file"

    let clientID: String
    let redirectURI: URL
    let callbackURLScheme: String
    let authorizationURL: URL
    let tokenURL: URL
    let revokeURL: URL
    let apiBaseURL: URL
    let uploadBaseURL: URL

    init(
        clientID: String,
        redirectURI: URL? = nil,
        callbackURLScheme: String? = nil,
        authorizationURL: URL = URL(string: "https://accounts.google.com/o/oauth2/v2/auth")!,
        tokenURL: URL = URL(string: "https://oauth2.googleapis.com/token")!,
        revokeURL: URL = URL(string: "https://oauth2.googleapis.com/revoke")!,
        apiBaseURL: URL = URL(string: "https://www.googleapis.com/drive/v3")!,
        uploadBaseURL: URL = URL(string: "https://www.googleapis.com/upload/drive/v3")!
    ) {
        let scheme = callbackURLScheme ?? Self.callbackScheme(for: clientID)
        self.clientID = clientID
        self.redirectURI = redirectURI ?? URL(string: "\(scheme):/oauth2redirect")!
        self.callbackURLScheme = scheme
        self.authorizationURL = authorizationURL
        self.tokenURL = tokenURL
        self.revokeURL = revokeURL
        self.apiBaseURL = apiBaseURL
        self.uploadBaseURL = uploadBaseURL
    }

    private static func callbackScheme(for clientID: String) -> String {
        let suffix = ".apps.googleusercontent.com"
        guard clientID.hasSuffix(suffix) else {
            return "com.chocoford.excalidraw.google-drive"
        }
        return "com.googleusercontent.apps.\(clientID.dropLast(suffix.count))"
    }
}
