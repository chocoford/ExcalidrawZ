//
//  DropboxConfiguration.swift
//  ExcalidrawZ
//

import Foundation

struct DropboxConfiguration: Sendable {
    let appKey: String
    let redirectURI: URL
    let callbackURLScheme: String
    let authorizationURL: URL
    let tokenURL: URL
    let apiBaseURL: URL
    let contentBaseURL: URL
    let scopes: [String]

    init(
        appKey: String,
        redirectURI: URL? = nil,
        callbackURLScheme: String? = nil,
        authorizationURL: URL = URL(string: "https://www.dropbox.com/oauth2/authorize")!,
        tokenURL: URL = URL(string: "https://api.dropboxapi.com/oauth2/token")!,
        apiBaseURL: URL = URL(string: "https://api.dropboxapi.com/2")!,
        contentBaseURL: URL = URL(string: "https://content.dropboxapi.com/2")!,
        scopes: [String] = [
            "account_info.read",
            "files.metadata.read",
            "files.metadata.write",
            "files.content.read",
            "files.content.write",
        ]
    ) {
        let nativeCallbackURLScheme = callbackURLScheme ?? "db-\(appKey)"
        self.appKey = appKey
        self.redirectURI = redirectURI
            ?? URL(string: "\(nativeCallbackURLScheme)://2/token")!
        self.callbackURLScheme = nativeCallbackURLScheme
        self.authorizationURL = authorizationURL
        self.tokenURL = tokenURL
        self.apiBaseURL = apiBaseURL
        self.contentBaseURL = contentBaseURL
        self.scopes = scopes
    }

    /// The callback scheme is the single source of truth for the public
    /// Dropbox app key, following Dropbox's `db-<APP_KEY>` convention.
    static func appKey(in bundle: Bundle) -> String? {
        let urlTypes = bundle.object(forInfoDictionaryKey: "CFBundleURLTypes")
            as? [[String: Any]] ?? []
        let schemes = urlTypes.flatMap {
            $0["CFBundleURLSchemes"] as? [String] ?? []
        }
        return appKey(fromURLSchemes: schemes)
    }

    static func appKey(fromURLSchemes schemes: [String]) -> String? {
        guard let scheme = schemes.first(where: { $0.hasPrefix("db-") }) else {
            return nil
        }
        let appKey = scheme.dropFirst(3)
        return appKey.isEmpty ? nil : String(appKey)
    }
}
