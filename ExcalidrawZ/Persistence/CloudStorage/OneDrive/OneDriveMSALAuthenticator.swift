//
//  OneDriveMSALAuthenticator.swift
//  ExcalidrawZ
//

import Foundation
import Logging
import MSAL

#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif

private let oneDriveAuthenticationLogger = Logger(label: "OneDriveMSALAuthenticator")

@MainActor
final class OneDriveMSALAuthenticator: OneDriveAuthenticating {
    private let configuration: OneDriveConfiguration
    private let application: MSALPublicClientApplication

    init(configuration: OneDriveConfiguration) throws {
        let authority = try MSALAADAuthority(url: configuration.authorityURL)
        let applicationConfiguration = MSALPublicClientApplicationConfig(
            clientId: configuration.clientID,
            redirectUri: configuration.redirectURI,
            authority: authority
        )

        self.configuration = configuration
        self.application = try MSALPublicClientApplication(
            configuration: applicationConfiguration
        )
    }

    func accounts() async throws -> [CloudStorageAccount] {
        try application.allAccounts().compactMap(Self.cloudStorageAccount(from:))
    }

    func authorize() async throws -> CloudStorageAccount {
        let result = try await acquireTokenInteractively()
        guard let account = Self.cloudStorageAccount(from: result.account) else {
            throw CloudStorageError.invalidProviderResponse(
                "Microsoft authentication returned an account without an identifier."
            )
        }
        return account
    }

    func accessToken(for accountID: CloudStorageAccountID) async throws -> String {
        let account: MSALAccount
        do {
            guard let cachedAccount = try application.allAccounts().first(where: {
                $0.identifier == accountID.rawValue
            }) else {
                throw CloudStorageError.accountUnavailable(accountID)
            }
            account = cachedAccount
        } catch {
            if let cloudStorageError = error as? CloudStorageError {
                throw cloudStorageError
            }
            throw Self.map(error)
        }

        let parameters = MSALSilentTokenParameters(
            scopes: configuration.scopes,
            account: account
        )
        return try await withCheckedThrowingContinuation { continuation in
            application.acquireTokenSilent(with: parameters) { result, error in
                if let result {
                    continuation.resume(returning: result.accessToken)
                } else {
                    continuation.resume(throwing: Self.map(error))
                }
            }
        }
    }

    func signOut(accountID: CloudStorageAccountID) async throws {
        do {
            guard let account = try application.allAccounts().first(where: {
                $0.identifier == accountID.rawValue
            }) else {
                return
            }
            try application.remove(account)
        } catch {
            throw Self.map(error)
        }
    }

    private func acquireTokenInteractively() async throws -> MSALResult {
        let webParameters = MSALWebviewParameters(
            authPresentationViewController: try presentationViewController()
        )
        let parameters = MSALInteractiveTokenParameters(
            scopes: configuration.scopes,
            webviewParameters: webParameters
        )

        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                application.acquireToken(with: parameters) { result, error in
                    if let result {
                        continuation.resume(returning: result)
                    } else {
                        continuation.resume(throwing: Self.map(error))
                    }
                }
            }
        } onCancel: {
            Task { @MainActor in
                _ = MSALPublicClientApplication.cancelCurrentWebAuthSession()
            }
        }
    }

#if os(macOS)
    private func presentationViewController() throws -> NSViewController {
        guard let window = NSApp.keyWindow
                ?? NSApp.mainWindow
                ?? NSApp.windows.first(where: { $0.isVisible }),
              let viewController = window.contentViewController else {
            throw CloudStorageError.transport(
                "A visible window is required to sign in to OneDrive."
            )
        }
        return viewController
    }
#elseif os(iOS)
    private func presentationViewController() throws -> UIViewController {
        let scenes = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .sorted { lhs, rhs in
                lhs.activationState == .foregroundActive
                    && rhs.activationState != .foregroundActive
            }
        guard let rootViewController = scenes
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)?
            .rootViewController else {
            throw CloudStorageError.transport(
                "A visible window is required to sign in to OneDrive."
            )
        }
        return rootViewController.topmostPresentedViewController
    }
#endif

    private static func cloudStorageAccount(from account: MSALAccount) -> CloudStorageAccount? {
        guard let identifier = account.identifier else { return nil }
        let emailAddress = account.username
        let displayName = account.accountClaims?["name"] as? String
            ?? emailAddress
            ?? "Microsoft Account"
        return CloudStorageAccount(
            providerID: .microsoftOneDrive,
            id: CloudStorageAccountID(rawValue: identifier),
            displayName: displayName,
            emailAddress: emailAddress
        )
    }

    nonisolated private static func map(_ error: Error?) -> Error {
        guard let sourceError = error else {
            return CloudStorageError.invalidProviderResponse(
                "Microsoft authentication completed without a result."
            )
        }
        let error = sourceError as NSError
        if error.domain == MSALErrorDomain {
            switch error.code {
                case MSALError.userCanceled.rawValue:
                    return CloudStorageError.authorizationCancelled
                case MSALError.interactionRequired.rawValue:
                    return CloudStorageError.authenticationRequired
                default:
                    break
            }
        }

        let diagnostic = diagnosticDescription(for: error)
        oneDriveAuthenticationLogger.error("Microsoft authentication failed: \(diagnostic.logMessage)")
        return CloudStorageError.transport(diagnostic.userMessage)
    }

    nonisolated private static func diagnosticDescription(
        for error: NSError
    ) -> (userMessage: String, logMessage: String) {
        let internalCode = error.userInfo[MSALInternalErrorCodeKey]
            .map { String(describing: $0) }
        let extendedDescription = error.userInfo[MSALErrorDescriptionKey] as? String
        let oauthError = error.userInfo[MSALOAuthErrorKey] as? String
        let oauthSuberror = error.userInfo[MSALOAuthSubErrorKey] as? String
        let responseCode = error.userInfo[MSALHTTPResponseCodeKey]
            .map { String(describing: $0) }
        let correlationID = error.userInfo[MSALCorrelationIDKey]
            .map { String(describing: $0) }
        let underlyingError = error.userInfo[NSUnderlyingErrorKey] as? NSError

        let bestDescription = [
            extendedDescription,
            error.localizedFailureReason,
            underlyingError?.localizedDescription,
            error.localizedDescription,
        ]
        .compactMap { $0 }
        .first { !$0.isEmpty }
            ?? "Microsoft authentication failed."

        let internalCodeSuffix = internalCode.map { " (MSAL internal code \($0))" } ?? ""
        let userMessage = bestDescription + internalCodeSuffix

        let logFields = [
            "domain=\(error.domain)",
            "code=\(error.code)",
            internalCode.map { "internalCode=\($0)" },
            oauthError.map { "oauthError=\($0)" },
            oauthSuberror.map { "oauthSuberror=\($0)" },
            responseCode.map { "httpStatus=\($0)" },
            correlationID.map { "correlationID=\($0)" },
            "description=\(bestDescription)",
            underlyingError.map {
                "underlyingDomain=\($0.domain) underlyingCode=\($0.code) underlyingDescription=\($0.localizedDescription)"
            },
        ]
        .compactMap { $0 }

        return (userMessage, logFields.joined(separator: " "))
    }
}

#if os(iOS)
private extension UIViewController {
    var topmostPresentedViewController: UIViewController {
        if let presentedViewController {
            return presentedViewController.topmostPresentedViewController
        }
        if let navigationController = self as? UINavigationController,
           let visibleViewController = navigationController.visibleViewController {
            return visibleViewController.topmostPresentedViewController
        }
        if let tabBarController = self as? UITabBarController,
           let selectedViewController = tabBarController.selectedViewController {
            return selectedViewController.topmostPresentedViewController
        }
        return self
    }
}
#endif
