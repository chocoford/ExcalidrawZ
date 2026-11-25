//
//  CloudStorageServerConnectionSheet.swift
//  ExcalidrawZ
//

import SwiftUI

struct CloudStorageServerConnectionSheet: View {
    @Environment(\.dismiss) private var dismiss

    let providerName: String
    let connectedAccounts: [CloudStorageAccount]
    let onSelectAccount: @MainActor (CloudStorageAccount) async throws -> Void
    let onConnect: @MainActor (CloudStorageServerCredentials) async throws -> Void

    @State private var serverURL = "https://"
    @State private var username = ""
    @State private var password = ""
    @State private var isConnecting = false
    @State private var openingAccountID: CloudStorageAccountID?
    @State private var errorMessage: String?
    @State private var operationTask: Task<Void, Never>?

    init(
        providerName: String,
        connectedAccounts: [CloudStorageAccount] = [],
        onSelectAccount: @escaping @MainActor (CloudStorageAccount) async throws -> Void = { _ in },
        onConnect: @escaping @MainActor (CloudStorageServerCredentials) async throws -> Void
    ) {
        self.providerName = providerName
        self.connectedAccounts = connectedAccounts
        self.onSelectAccount = onSelectAccount
        self.onConnect = onConnect
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                WebDAVServiceMarqueeHeader()
                header
            }

            Form {
                Section {
                    TextField(String(localizable: .cloudStorageServerURL), text: $serverURL)
#if os(iOS)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
#endif
                        .autocorrectionDisabled()

                    TextField(String(localizable: .cloudStorageUsername), text: $username)
#if os(iOS)
                        .textInputAutocapitalization(.never)
#endif
                        .autocorrectionDisabled()

                    SecureField(String(localizable: .cloudStoragePasswordOrAppPassword), text: $password)
                } header: {
                    Text(.localizable(.cloudStorageWebDAVAccount))
                } footer: {
                    VStack(alignment: .leading, spacing: 12) {
                        if let detectedServiceName {
                            Text(.localizable(.cloudStorageDetectedServiceFormat(detectedServiceName)))
                        }
                        Text(.localizable(.cloudStorageWebDAVCredentialsDescription))

                        Button {
                            connect()
                        } label: {
                            HStack(spacing: 8) {
                                if isConnecting {
                                    ProgressView()
                                        .controlSize(.small)
                                }
                                Text(isConnecting
                                    ? String(localizable: .cloudStorageConnecting)
                                    : String(localizable: .cloudStorageConnect)
                                )
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .modernButtonStyle(style: .glassProminent, size: .large, shape: .modern)
                        .disabled(!canConnect || isConnecting)
                    }
                }

                if !connectedAccounts.isEmpty {
                    Section {
                        ForEach(connectedAccounts, id: \.id) { account in
                            connectedAccountRow(account)
                        }
                    } header: {
                        Text(.localizable(.cloudStorageConnectedAccounts))
                    } footer: {
                        Text(.localizable(.cloudStorageConnectedAccountsDescription))
                    }
                }

                if let errorMessage {
                    Section {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    }
                }
            }
            .formStyle(.grouped)
            .disabled(isOperationInProgress)
        }
        .onDisappear {
            cancelOperation()
        }
#if os(macOS)
        .frame(minWidth: 620, idealWidth: 700, minHeight: 600, idealHeight: 680)
#endif
    }

    private var header: some View {
        ZStack {
            Text(.localizable(.cloudStorageConnectProviderFormat(providerName)))
                .font(.headline)
                .lineLimit(1)
                .truncationMode(.middle)
                .padding(.horizontal, 72)
                .frame(maxWidth: .infinity)

            HStack {
                Button {
                    dismissSheet()
                } label: {
                    Image(systemName: "xmark")
                }
                .modernButtonStyle(style: .glass, size: .large, shape: .circle)

                Spacer()
            }
            .padding(.horizontal, 12)
        }
        .frame(height: 68)
    }

    private var isOperationInProgress: Bool {
        isConnecting || openingAccountID != nil
    }

    private var canConnect: Bool {
        URL(string: serverURL.trimmingCharacters(in: .whitespacesAndNewlines)) != nil
            && !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !password.isEmpty
    }

    private var detectedServiceName: String? {
        guard let url = URL(
            string: serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
        ), url.host != nil else {
            return nil
        }
        return WebDAVServiceIdentity.displayName(for: url)
    }

    private func connectedAccountRow(_ account: CloudStorageAccount) -> some View {
        Button {
            open(account)
        } label: {
            HStack(spacing: 12) {
                CloudStorageProviderIcon(
                    providerID: account.providerID,
                    size: 28,
                    accountDisplayName: account.displayName
                )
                .frame(width: 32, height: 32)

                Text(account.displayName)
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Spacer(minLength: 12)

                if openingAccountID == account.id {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func open(_ account: CloudStorageAccount) {
        guard !isOperationInProgress else { return }
        openingAccountID = account.id
        errorMessage = nil
        operationTask = Task { @MainActor in
            defer {
                openingAccountID = nil
                operationTask = nil
            }
            do {
                try await onSelectAccount(account)
                try Task.checkCancellation()
            } catch is CancellationError {
                return
            } catch CloudStorageError.authorizationCancelled {
                return
            } catch {
                guard !Task.isCancelled else { return }
                errorMessage = error.localizedDescription
            }
        }
    }

    private func connect() {
        guard !isOperationInProgress else { return }
        let trimmedURL = serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmedURL) else { return }

        isConnecting = true
        errorMessage = nil
        operationTask = Task { @MainActor in
            defer {
                isConnecting = false
                operationTask = nil
            }
            do {
                try await onConnect(
                    CloudStorageServerCredentials(
                        serverURL: url,
                        username: username.trimmingCharacters(in: .whitespacesAndNewlines),
                        password: password
                    )
                )
                try Task.checkCancellation()
            } catch is CancellationError {
                return
            } catch CloudStorageError.authorizationCancelled {
                return
            } catch {
                guard !Task.isCancelled else { return }
                errorMessage = error.localizedDescription
            }
        }
    }

    private func dismissSheet() {
        cancelOperation()
        dismiss()
    }

    private func cancelOperation() {
        operationTask?.cancel()
        operationTask = nil
    }
}
