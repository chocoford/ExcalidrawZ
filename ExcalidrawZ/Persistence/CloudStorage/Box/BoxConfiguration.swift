//
//  BoxConfiguration.swift
//  ExcalidrawZ
//

import Foundation

struct BoxConfiguration: Sendable {
    let clientID: String
    let clientSecret: String
    let redirectURI: URL
    let callbackURLScheme: String
    let authorizationURL: URL
    let tokenURL: URL
    let revokeURL: URL
    let apiBaseURL: URL
    let uploadBaseURL: URL

    init(
        clientID: String,
        clientSecret: String,
        redirectURI: URL,
        callbackURLScheme: String = "excalidrawz",
        authorizationURL: URL = URL(string: "https://account.box.com/api/oauth2/authorize")!,
        tokenURL: URL = URL(string: "https://api.box.com/oauth2/token")!,
        revokeURL: URL = URL(string: "https://api.box.com/oauth2/revoke")!,
        apiBaseURL: URL = URL(string: "https://api.box.com/2.0")!,
        uploadBaseURL: URL = URL(string: "https://upload.box.com/api/2.0")!
    ) {
        self.clientID = clientID
        self.clientSecret = clientSecret
        self.redirectURI = redirectURI
        self.callbackURLScheme = callbackURLScheme
        self.authorizationURL = authorizationURL
        self.tokenURL = tokenURL
        self.revokeURL = revokeURL
        self.apiBaseURL = apiBaseURL
        self.uploadBaseURL = uploadBaseURL
    }
}
