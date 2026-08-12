//
//  BoxOAuthAuthenticator.swift
//  ExcalidrawZ
//

import AuthenticationServices
import Foundation
import Logging

#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif

@MainActor
final class BoxOAuthAuthenticator: NSObject, BoxAuthenticating {
    private let logger = Logger(label: "BoxOAuthAuthenticator")
    private let configuration: BoxConfiguration
    private let credentialStore: BoxCredentialStore
    private let urlSession: URLSession
    private var authenticationSession: ASWebAuthenticationSession?
    private var refreshTasks: [CloudStorageAccountID: Task<String, Error>] = [:]

    init(
        configuration: BoxConfiguration,
        credentialStore: BoxCredentialStore = BoxCredentialStore(),
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
        let state = UUID().uuidString
        let callbackURL = try await authenticate(state: state)
        let values = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let callbackState = values.first(where: { $0.name == "state" })?.value
        guard callbackState == state else {
            throw CloudStorageError.invalidProviderResponse("Box OAuth state did not match.")
        }
        if let oauthError = values.first(where: { $0.name == "error" })?.value {
            if oauthError == "access_denied" {
                throw CloudStorageError.authorizationCancelled
            }
            throw CloudStorageError.transport("Box authorization failed: \(oauthError)")
        }
        guard let code = values.first(where: { $0.name == "code" })?.value else {
            throw CloudStorageError.invalidProviderResponse(
                "Box authorization did not return an authorization code."
            )
        }

        let token = try await requestToken(parameters: [
            "grant_type": "authorization_code",
            "code": code,
            "client_id": configuration.clientID,
            "client_secret": configuration.clientSecret,
            "redirect_uri": configuration.redirectURI.absoluteString,
        ])
        let user = try await currentUser(accessToken: token.accessToken)
        guard let refreshToken = token.refreshToken else {
            throw CloudStorageError.invalidProviderResponse(
                "Box authorization did not return a refresh token."
            )
        }
        let credential = BoxCredential(
            accountID: user.id,
            displayName: user.name ?? user.login ?? "Box Account",
            emailAddress: user.login,
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
                    "client_id": configuration.clientID,
                    "client_secret": configuration.clientSecret,
                ]
            )
            guard let refreshToken = token.refreshToken else {
                throw CloudStorageError.invalidProviderResponse(
                    "Box token refresh did not return a replacement refresh token."
                )
            }
            let updated = BoxCredential(
                accountID: credential.accountID,
                displayName: credential.displayName,
                emailAddress: credential.emailAddress,
                accessToken: token.accessToken,
                refreshToken: refreshToken,
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
        guard let credential = try credentialStore.credential(for: accountID) else { return }
        do {
            _ = try await sendForm(
                to: configuration.revokeURL,
                parameters: [
                    "client_id": configuration.clientID,
                    "client_secret": configuration.clientSecret,
                    "token": credential.refreshToken,
                ]
            )
        } catch {
            logger.warning("Failed to revoke Box token; removing local credential: \(error)")
        }
        try credentialStore.remove(accountID: accountID)
    }

    private func authenticate(state: String) async throws -> URL {
        guard var components = URLComponents(
            url: configuration.authorizationURL,
            resolvingAgainstBaseURL: false
        ) else {
            throw CloudStorageError.invalidProviderResponse(
                "Unable to construct the Box authorization URL."
            )
        }
        components.queryItems = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: configuration.clientID),
            URLQueryItem(name: "redirect_uri", value: configuration.redirectURI.absoluteString),
            URLQueryItem(name: "state", value: state),
        ]
        guard let authorizationURL = components.url else {
            throw CloudStorageError.invalidProviderResponse(
                "Unable to construct the Box authorization URL."
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
                                error?.localizedDescription ?? "Box authorization did not return a result."
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
                        "Unable to start Box authorization."
                    ))
                }
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                self?.authenticationSession?.cancel()
            }
        }
    }

    private func requestToken(parameters: [String: String]) async throws -> BoxTokenResponse {
        try await Self.requestToken(
            configuration: configuration,
            urlSession: urlSession,
            parameters: parameters
        )
    }

    private static func requestToken(
        configuration: BoxConfiguration,
        urlSession: URLSession,
        parameters: [String: String]
    ) async throws -> BoxTokenResponse {
        let data = try await sendForm(
            urlSession: urlSession,
            to: configuration.tokenURL,
            parameters: parameters
        )
        do {
            return try JSONDecoder().decode(BoxTokenResponse.self, from: data)
        } catch {
            throw CloudStorageError.invalidProviderResponse(
                "Unable to decode Box token response: \(error.localizedDescription)"
            )
        }
    }

    private func currentUser(accessToken: String) async throws -> BoxUser {
        var components = URLComponents(
            url: configuration.apiBaseURL.appending(path: "users/me"),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [URLQueryItem(name: "fields", value: "id,name,login")]
        guard let userURL = components?.url else {
            throw CloudStorageError.invalidProviderResponse("Unable to construct Box user URL.")
        }
        var request = URLRequest(url: userURL)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await urlSession.data(for: request)
        try Self.validateOAuthResponse(response, data: data)
        return try JSONDecoder().decode(BoxUser.self, from: data)
    }

    private func sendForm(to url: URL, parameters: [String: String]) async throws -> Data {
        try await Self.sendForm(urlSession: urlSession, to: url, parameters: parameters)
    }

    private static func sendForm(
        urlSession: URLSession,
        to url: URL,
        parameters: [String: String]
    ) async throws -> Data {
        var components = URLComponents()
        components.queryItems = parameters.map { URLQueryItem(name: $0.key, value: $0.value) }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = components.percentEncodedQuery?.data(using: .utf8)
        let (data, response) = try await urlSession.data(for: request)
        try validateOAuthResponse(response, data: data)
        return data
    }

    private static func validateOAuthResponse(_ response: URLResponse, data: Data) throws {
        guard let response = response as? HTTPURLResponse else {
            throw CloudStorageError.invalidProviderResponse("Missing Box HTTP response.")
        }
        guard (200..<300).contains(response.statusCode) else {
            let error = try? JSONDecoder().decode(BoxOAuthError.self, from: data)
            if response.statusCode == 401 || error?.error == "invalid_grant" {
                throw CloudStorageError.authenticationRequired
            }
            throw CloudStorageError.transport(
                error?.errorDescription ?? error?.error ?? "Box returned HTTP \(response.statusCode)."
            )
        }
    }
}

extension BoxOAuthAuthenticator: ASWebAuthenticationPresentationContextProviding {
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

private struct BoxTokenResponse: Decodable {
    let accessToken: String
    let refreshToken: String?
    let expiresIn: TimeInterval

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
    }
}

private struct BoxUser: Decodable {
    let id: String
    let name: String?
    let login: String?
}

private struct BoxOAuthError: Decodable {
    let error: String?
    let errorDescription: String?

    enum CodingKeys: String, CodingKey {
        case error
        case errorDescription = "error_description"
    }
}
