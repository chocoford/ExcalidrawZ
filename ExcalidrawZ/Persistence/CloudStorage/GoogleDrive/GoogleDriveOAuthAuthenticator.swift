//
//  GoogleDriveOAuthAuthenticator.swift
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
final class GoogleDriveOAuthAuthenticator: NSObject, GoogleDriveAuthenticating {
    private let logger = Logger(label: "GoogleDriveOAuthAuthenticator")
    private let configuration: GoogleDriveConfiguration
    private let credentialStore: GoogleDriveCredentialStore
    private let urlSession: URLSession
    private var authenticationSession: ASWebAuthenticationSession?
    private var refreshTasks: [CloudStorageAccountID: Task<String, Error>] = [:]

    init(
        configuration: GoogleDriveConfiguration,
        credentialStore: GoogleDriveCredentialStore = GoogleDriveCredentialStore(),
        urlSession: URLSession = .shared
    ) {
        self.configuration = configuration
        self.credentialStore = credentialStore
        self.urlSession = urlSession
    }

    func accounts() async throws -> [CloudStorageAccount] {
        try credentialStore.credentials()
            .map(\.cloudStorageAccount)
            .sorted {
                $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
            }
    }

    func authorize() async throws -> CloudStorageAccount {
        try await performAuthorization(accountHint: nil)
    }

    func accountWithRequiredScope(
        accountHint: CloudStorageAccount?
    ) async throws -> CloudStorageAccount {
        if let accountHint,
           let credential = try credentialStore.credential(for: accountHint.id),
           credential.hasRequiredScope {
            return credential.cloudStorageAccount
        }
        return try await performAuthorization(accountHint: accountHint)
    }

    func accessToken(for accountID: CloudStorageAccountID) async throws -> String {
        guard let credential = try credentialStore.credential(for: accountID) else {
            throw CloudStorageError.accountUnavailable(accountID)
        }
        guard credential.hasRequiredScope else {
            throw CloudStorageError.authenticationRequired
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
                    "client_id": configuration.clientID,
                    "grant_type": "refresh_token",
                    "refresh_token": credential.refreshToken,
                ]
            )
            let updated = GoogleDriveCredential(
                accountID: credential.accountID,
                displayName: credential.displayName,
                emailAddress: credential.emailAddress,
                accessToken: token.accessToken,
                refreshToken: token.refreshToken ?? credential.refreshToken,
                expiresAt: Date().addingTimeInterval(token.expiresIn),
                grantedScopes: credential.grantedScopes
            )
            try credentialStore.save(updated)
            return updated.accessToken
        }
        refreshTasks[accountID] = task
        defer { refreshTasks[accountID] = nil }
        return try await task.value
    }

    func signOut(accountID: CloudStorageAccountID) async throws {
        guard let credential = try credentialStore.credential(for: accountID) else { return }
        do {
            var components = URLComponents(
                url: configuration.revokeURL,
                resolvingAgainstBaseURL: false
            )
            components?.queryItems = [
                URLQueryItem(name: "token", value: credential.refreshToken),
            ]
            guard let url = components?.url else {
                throw CloudStorageError.invalidProviderResponse(
                    "Unable to construct Google token revocation URL."
                )
            }
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            let (_, response) = try await urlSession.data(for: request)
            guard let response = response as? HTTPURLResponse,
                  (200..<300).contains(response.statusCode) else {
                throw CloudStorageError.transport("Google rejected token revocation.")
            }
        } catch {
            logger.warning("Failed to revoke Google token; removing local credential: \(error)")
        }
        try credentialStore.remove(accountID: accountID)
    }

    private func performAuthorization(
        accountHint: CloudStorageAccount?
    ) async throws -> CloudStorageAccount {
        let state = UUID().uuidString
        let verifier = try Self.makeCodeVerifier()
        let callbackURL = try await authenticate(
            state: state,
            codeChallenge: Self.codeChallenge(for: verifier),
            accountHint: accountHint
        )
        let values = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)?.queryItems ?? []
        guard values.first(where: { $0.name == "state" })?.value == state else {
            throw CloudStorageError.invalidProviderResponse("Google OAuth state did not match.")
        }
        if let oauthError = values.first(where: { $0.name == "error" })?.value {
            if oauthError == "access_denied" {
                throw CloudStorageError.authorizationCancelled
            }
            throw CloudStorageError.transport("Google authorization failed: \(oauthError)")
        }
        guard let code = values.first(where: { $0.name == "code" })?.value else {
            throw CloudStorageError.invalidProviderResponse(
                "Google authorization did not return an authorization code."
            )
        }

        let token = try await requestToken(parameters: [
            "client_id": configuration.clientID,
            "code": code,
            "code_verifier": verifier,
            "grant_type": "authorization_code",
            "redirect_uri": configuration.redirectURI.absoluteString,
        ])
        let user = try await currentUser(accessToken: token.accessToken)
        let accountID = CloudStorageAccountID(rawValue: user.permissionId)
        let existingCredential = try credentialStore.credential(for: accountID)
        guard let refreshToken = token.refreshToken ?? existingCredential?.refreshToken else {
            throw CloudStorageError.invalidProviderResponse(
                "Google authorization did not return a refresh token. Revoke ExcalidrawZ access in your Google Account and try again."
            )
        }
        let credential = GoogleDriveCredential(
            accountID: user.permissionId,
            displayName: user.displayName ?? user.emailAddress ?? "Google Drive",
            emailAddress: user.emailAddress,
            accessToken: token.accessToken,
            refreshToken: refreshToken,
            expiresAt: Date().addingTimeInterval(token.expiresIn),
            grantedScopes: [GoogleDriveConfiguration.driveScope]
        )
        try credentialStore.save(credential)
        return credential.cloudStorageAccount
    }

    private func authenticate(
        state: String,
        codeChallenge: String,
        accountHint: CloudStorageAccount?
    ) async throws -> URL {
        guard var components = URLComponents(
            url: configuration.authorizationURL,
            resolvingAgainstBaseURL: false
        ) else {
            throw CloudStorageError.invalidProviderResponse(
                "Unable to construct the Google authorization URL."
            )
        }
        var queryItems = [
            URLQueryItem(name: "client_id", value: configuration.clientID),
            URLQueryItem(name: "redirect_uri", value: configuration.redirectURI.absoluteString),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: GoogleDriveConfiguration.driveScope),
            URLQueryItem(name: "access_type", value: "offline"),
            URLQueryItem(name: "prompt", value: "consent"),
            URLQueryItem(name: "include_granted_scopes", value: "false"),
            URLQueryItem(name: "code_challenge", value: codeChallenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: state),
        ]
        if let loginHint = accountHint?.emailAddress {
            queryItems.append(URLQueryItem(name: "login_hint", value: loginHint))
        }
        components.queryItems = queryItems
        guard let authorizationURL = components.url else {
            throw CloudStorageError.invalidProviderResponse(
                "Unable to construct the Google authorization URL."
            )
        }

        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
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
                                    ?? "Google authorization did not return a result."
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
                        "Unable to start Google authorization."
                    ))
                }
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                self?.authenticationSession?.cancel()
            }
        }
    }

    private func requestToken(parameters: [String: String]) async throws -> GoogleDriveTokenResponse {
        try await Self.requestToken(
            configuration: configuration,
            urlSession: urlSession,
            parameters: parameters
        )
    }

    private static func requestToken(
        configuration: GoogleDriveConfiguration,
        urlSession: URLSession,
        parameters: [String: String]
    ) async throws -> GoogleDriveTokenResponse {
        var components = URLComponents()
        components.queryItems = parameters.map { URLQueryItem(name: $0.key, value: $0.value) }
        var request = URLRequest(url: configuration.tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = components.percentEncodedQuery?.data(using: .utf8)
        let (data, response) = try await urlSession.data(for: request)
        try validateOAuthResponse(response, data: data)
        do {
            return try JSONDecoder().decode(GoogleDriveTokenResponse.self, from: data)
        } catch {
            throw CloudStorageError.invalidProviderResponse(
                "Unable to decode Google token response: \(error.localizedDescription)"
            )
        }
    }

    private func currentUser(accessToken: String) async throws -> GoogleDriveAbout.User {
        var components = URLComponents(
            url: configuration.apiBaseURL.appending(path: "about"),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [URLQueryItem(name: "fields", value: "user")]
        guard let url = components?.url else {
            throw CloudStorageError.invalidProviderResponse("Unable to construct Google Drive about URL.")
        }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await urlSession.data(for: request)
        try Self.validateOAuthResponse(response, data: data)
        do {
            return try JSONDecoder.googleDriveDecoder().decode(GoogleDriveAbout.self, from: data).user
        } catch {
            throw CloudStorageError.invalidProviderResponse(
                "Unable to decode Google Drive account response: \(error.localizedDescription)"
            )
        }
    }

    private static func validateOAuthResponse(_ response: URLResponse, data: Data) throws {
        guard let response = response as? HTTPURLResponse else {
            throw CloudStorageError.invalidProviderResponse("Missing Google OAuth HTTP response.")
        }
        guard (200..<300).contains(response.statusCode) else {
            let error = try? JSONDecoder().decode(GoogleDriveOAuthError.self, from: data)
            if response.statusCode == 401 || error?.error == "invalid_grant" {
                throw CloudStorageError.authenticationRequired
            }
            throw CloudStorageError.transport(
                error?.errorDescription ?? error?.error
                    ?? "Google OAuth returned HTTP \(response.statusCode)."
            )
        }
    }

    nonisolated private static func makeCodeVerifier() throws -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
            throw CloudStorageError.transport("Unable to create Google OAuth PKCE verifier.")
        }
        return Data(bytes).base64URLEncodedString()
    }

    nonisolated private static func codeChallenge(for verifier: String) -> String {
        Data(SHA256.hash(data: Data(verifier.utf8))).base64URLEncodedString()
    }
}

extension GoogleDriveOAuthAuthenticator: ASWebAuthenticationPresentationContextProviding {
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

private struct GoogleDriveTokenResponse: Decodable {
    let accessToken: String
    let expiresIn: TimeInterval
    let refreshToken: String?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case expiresIn = "expires_in"
        case refreshToken = "refresh_token"
    }
}

private struct GoogleDriveOAuthError: Decodable {
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
