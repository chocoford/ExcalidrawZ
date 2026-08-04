//
//  DropboxOAuthAuthenticator.swift
//  ExcalidrawZ
//

import AuthenticationServices
import CryptoKit
import Foundation
import Logging
import Security

#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif

@MainActor
final class DropboxOAuthAuthenticator: NSObject, DropboxAuthenticating {
    private let logger = Logger(label: "DropboxOAuthAuthenticator")
    private let configuration: DropboxConfiguration
    private let credentialStore: DropboxCredentialStore
    private let urlSession: URLSession
    private var authenticationSession: ASWebAuthenticationSession?
    private var refreshTasks: [CloudStorageAccountID: Task<String, Error>] = [:]

    init(
        configuration: DropboxConfiguration,
        credentialStore: DropboxCredentialStore = DropboxCredentialStore(),
        urlSession: URLSession = .shared
    ) {
        self.configuration = configuration
        self.credentialStore = credentialStore
        self.urlSession = urlSession
    }

    func accounts() async throws -> [CloudStorageAccount] {
        do {
            let credentials = try credentialStore.credentials()
#if DEBUG
            logger.debug("Restored Dropbox credentials count=\(credentials.count)")
#endif
            return credentials
                .map(\.cloudStorageAccount)
                .sorted {
                    $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
                }
        } catch {
            logger.error("Failed to restore Dropbox credentials: \(error)")
            throw error
        }
    }

    func authorize() async throws -> CloudStorageAccount {
        let state = UUID().uuidString
        let verifier = try Self.makeCodeVerifier()
        let callbackURL = try await authenticate(
            state: state,
            codeChallenge: Self.codeChallenge(for: verifier)
        )
        let queryItems = URLComponents(
            url: callbackURL,
            resolvingAgainstBaseURL: false
        )?.queryItems ?? []
        guard queryItems.first(where: { $0.name == "state" })?.value == state else {
            throw CloudStorageError.invalidProviderResponse(
                "Dropbox OAuth state did not match."
            )
        }
        if let oauthError = queryItems.first(where: { $0.name == "error" })?.value {
            if oauthError == "access_denied" {
                throw CloudStorageError.authorizationCancelled
            }
            let description = queryItems
                .first(where: { $0.name == "error_description" })?.value
            throw CloudStorageError.transport(description ?? "Dropbox authorization failed: \(oauthError)")
        }
        guard let code = queryItems.first(where: { $0.name == "code" })?.value else {
            throw CloudStorageError.invalidProviderResponse(
                "Dropbox authorization did not return an authorization code."
            )
        }

        let token = try await requestToken(parameters: [
            "grant_type": "authorization_code",
            "code": code,
            "code_verifier": verifier,
            "client_id": configuration.appKey,
            "redirect_uri": configuration.redirectURI.absoluteString,
        ])
        guard let refreshToken = token.refreshToken else {
            throw CloudStorageError.invalidProviderResponse(
                "Dropbox authorization did not return a refresh token."
            )
        }
        let user = try await currentAccount(accessToken: token.accessToken)
        let credential = DropboxCredential(
            accountID: user.accountID,
            displayName: user.name.displayName,
            emailAddress: user.email,
            accessToken: token.accessToken,
            refreshToken: refreshToken,
            expiresAt: Date().addingTimeInterval(token.expiresIn)
        )
        try credentialStore.save(credential)
        return credential.cloudStorageAccount
    }

    func accessToken(for accountID: CloudStorageAccountID) async throws -> String {
        guard let credential = try credentialStore.credential(for: accountID) else {
            throw CloudStorageError.accountUnavailable(accountID)
        }
        if credential.expiresAt.timeIntervalSinceNow > 60 {
            return credential.accessToken
        }
        if let task = refreshTasks[accountID] {
            return try await task.value
        }

        let task = Task { @MainActor [configuration, credentialStore, urlSession] in
            let token = try await Self.requestToken(
                configuration: configuration,
                urlSession: urlSession,
                parameters: [
                    "grant_type": "refresh_token",
                    "refresh_token": credential.refreshToken,
                    "client_id": configuration.appKey,
                ]
            )
            let updated = DropboxCredential(
                accountID: credential.accountID,
                displayName: credential.displayName,
                emailAddress: credential.emailAddress,
                accessToken: token.accessToken,
                refreshToken: token.refreshToken ?? credential.refreshToken,
                expiresAt: Date().addingTimeInterval(token.expiresIn)
            )
            try credentialStore.save(updated)
            return updated.accessToken
        }
        refreshTasks[accountID] = task
        defer { refreshTasks[accountID] = nil }
        return try await task.value
    }

    func signOut(accountID: CloudStorageAccountID) async throws {
        guard try credentialStore.credential(for: accountID) != nil else { return }
        do {
            let token = try await accessToken(for: accountID)
            var request = URLRequest(
                url: configuration.apiBaseURL.appending(path: "auth/token/revoke")
            )
            request.httpMethod = "POST"
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            let (data, response) = try await urlSession.data(for: request)
            try Self.validateResponse(response, data: data)
        } catch {
            logger.warning("Failed to revoke Dropbox token; removing local credential: \(error)")
        }
        try credentialStore.remove(accountID: accountID)
    }

    private func authenticate(
        state: String,
        codeChallenge: String
    ) async throws -> URL {
        guard var components = URLComponents(
            url: configuration.authorizationURL,
            resolvingAgainstBaseURL: false
        ) else {
            throw CloudStorageError.invalidProviderResponse(
                "Unable to construct the Dropbox authorization URL."
            )
        }
        components.queryItems = [
            URLQueryItem(name: "client_id", value: configuration.appKey),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: configuration.redirectURI.absoluteString),
            URLQueryItem(name: "token_access_type", value: "offline"),
            URLQueryItem(name: "code_challenge", value: codeChallenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "scope", value: configuration.scopes.joined(separator: " ")),
            URLQueryItem(name: "state", value: state),
        ]
        guard let authorizationURL = components.url else {
            throw CloudStorageError.invalidProviderResponse(
                "Unable to construct the Dropbox authorization URL."
            )
        }

        return try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: authorizationURL,
                callbackURLScheme: configuration.callbackURLScheme
            ) { [weak self] callbackURL, error in
                Task { @MainActor in
                    self?.authenticationSession = nil
                    if let callbackURL {
                        continuation.resume(returning: callbackURL)
                    } else if let error = error as? ASWebAuthenticationSessionError,
                              error.code == .canceledLogin {
                        continuation.resume(throwing: CloudStorageError.authorizationCancelled)
                    } else {
                        continuation.resume(throwing: CloudStorageError.transport(
                            error?.localizedDescription
                                ?? "Dropbox authorization did not return a result."
                        ))
                    }
                }
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            authenticationSession = session
            if !session.start() {
                authenticationSession = nil
                continuation.resume(throwing: CloudStorageError.transport(
                    "Unable to start Dropbox authorization."
                ))
            }
        }
    }

    private func requestToken(parameters: [String: String]) async throws -> DropboxTokenResponse {
        try await Self.requestToken(
            configuration: configuration,
            urlSession: urlSession,
            parameters: parameters
        )
    }

    private static func requestToken(
        configuration: DropboxConfiguration,
        urlSession: URLSession,
        parameters: [String: String]
    ) async throws -> DropboxTokenResponse {
        var components = URLComponents()
        components.queryItems = parameters.map { URLQueryItem(name: $0.key, value: $0.value) }
        var request = URLRequest(url: configuration.tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = components.percentEncodedQuery?.data(using: .utf8)
        let (data, response) = try await urlSession.data(for: request)
        try validateResponse(response, data: data)
        do {
            return try JSONDecoder().decode(DropboxTokenResponse.self, from: data)
        } catch {
            throw CloudStorageError.invalidProviderResponse(
                "Unable to decode Dropbox token response: \(error.localizedDescription)"
            )
        }
    }

    private func currentAccount(accessToken: String) async throws -> DropboxCurrentAccount {
        var request = URLRequest(
            url: configuration.apiBaseURL.appending(path: "users/get_current_account")
        )
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data("null".utf8)
        let (data, response) = try await urlSession.data(for: request)
        try Self.validateResponse(response, data: data)
        do {
            return try JSONDecoder().decode(DropboxCurrentAccount.self, from: data)
        } catch {
            throw CloudStorageError.invalidProviderResponse(
                "Unable to decode Dropbox account response: \(error.localizedDescription)"
            )
        }
    }

    private static func validateResponse(_ response: URLResponse, data: Data) throws {
        guard let response = response as? HTTPURLResponse else {
            throw CloudStorageError.invalidProviderResponse("Missing Dropbox HTTP response.")
        }
        guard (200..<300).contains(response.statusCode) else {
            let error = try? JSONDecoder().decode(DropboxOAuthError.self, from: data)
            if response.statusCode == 401 || error?.error == "invalid_grant" {
                throw CloudStorageError.authenticationRequired
            }
            throw CloudStorageError.transport(
                error?.errorDescription ?? error?.error
                    ?? "Dropbox returned HTTP \(response.statusCode)."
            )
        }
    }

    nonisolated private static func makeCodeVerifier() throws -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
            throw CloudStorageError.transport("Unable to create Dropbox PKCE verifier.")
        }
        return Data(bytes).base64URLEncodedString()
    }

    nonisolated private static func codeChallenge(for verifier: String) -> String {
        Data(SHA256.hash(data: Data(verifier.utf8))).base64URLEncodedString()
    }
}

extension DropboxOAuthAuthenticator: ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
#if os(macOS)
        NSApp.keyWindow ?? NSApp.mainWindow ?? NSApp.windows.first(where: \.isVisible) ?? NSWindow()
#else
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow) ?? UIWindow()
#endif
    }
}

private struct DropboxTokenResponse: Decodable {
    let accessToken: String
    let expiresIn: TimeInterval
    let refreshToken: String?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case expiresIn = "expires_in"
        case refreshToken = "refresh_token"
    }
}

private struct DropboxCurrentAccount: Decodable {
    struct Name: Decodable {
        let displayName: String

        enum CodingKeys: String, CodingKey {
            case displayName = "display_name"
        }
    }

    let accountID: String
    let name: Name
    let email: String?

    enum CodingKeys: String, CodingKey {
        case accountID = "account_id"
        case name
        case email
    }
}

private struct DropboxOAuthError: Decodable {
    let error: String?
    let errorDescription: String?

    enum CodingKeys: String, CodingKey {
        case error
        case errorDescription = "error_description"
    }
}

private extension Data {
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
