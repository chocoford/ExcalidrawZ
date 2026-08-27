//
//  CloudStorageSettingsView.swift
//  ExcalidrawZ
//

import SwiftUI

struct CloudStorageSettingsView: View {
    private struct AccountEntry: Identifiable {
        let account: CloudStorageAccount
        let providerName: String

        var id: String {
            "\(account.providerID.rawValue):\(account.id.rawValue)"
        }
    }

    @Environment(\.alertToast) private var alertToast

    @StateObject private var connections = CloudStorageConnectionStore.shared
    @State private var disconnectRequest: AccountEntry?
    @State private var disconnectingAccountID: String?

    var body: some View {
        SettingsFormContainer(legacyAlignment: .leading) {
            Section {
                if accounts.isEmpty {
                    emptyState
                } else {
                    ForEach(accounts) { entry in
                        accountRow(entry)
                    }
                }
            } header: {
                Text(.localizable(.cloudStorageConnectedAccounts))
            } footer: {
                Text(.localizable(.settingsCloudStorageDisconnectDescription))
            }
        }
        .navigationTitle(.localizable(.cloudStorageConnectedAccounts))
        .task {
            await connections.refresh()
        }
        .alert(item: $disconnectRequest) { entry in
            Alert(
                title: Text(.localizable(.settingsCloudStorageDisconnectTitle)),
                message: Text(.localizable(.settingsCloudStorageDisconnectMessage(
                    entry.account.displayName,
                    entry.providerName
                ))),
                primaryButton: .destructive(Text(.localizable(.settingsCloudStorageDisconnectAction))) {
                    disconnect(entry)
                },
                secondaryButton: .cancel()
            )
        }
    }

    private var accounts: [AccountEntry] {
        connections.providerDescriptors.flatMap { descriptor in
            connections.accounts(for: descriptor.id).map {
                AccountEntry(account: $0, providerName: descriptor.displayName)
            }
        }
    }

    private var emptyState: some View {
        HStack(spacing: 14) {
            Image(systemName: "person.crop.circle.badge.checkmark")
                .font(.title2)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 3) {
                Text(.localizable(.settingsCloudStorageNoConnectedAccounts))
                    .font(.headline)
                Text(.localizable(.settingsCloudStorageNoConnectedAccountsDescription))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 8)
    }

    private func accountRow(_ entry: AccountEntry) -> some View {
        HStack(spacing: 14) {
            CloudStorageProviderIcon(
                providerID: entry.account.providerID,
                size: 32,
                accountDisplayName: entry.account.displayName
            )
            .frame(width: 38, height: 38)

            VStack(alignment: .leading, spacing: 3) {
                Text(entry.account.displayName)
                    .font(.body.weight(.medium))
                    .lineLimit(1)

                Text(accountCaption(entry))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 16)

            if disconnectingAccountID == entry.id {
                ProgressView()
                    .controlSize(.small)
            } else {
                Button(.localizable(.settingsCloudStorageDisconnectAction), role: .destructive) {
                    disconnectRequest = entry
                }
                .buttonStyle(.bordered)
                .tint(.red)
            }
        }
        .padding(.vertical, 6)
    }

    private func accountCaption(_ entry: AccountEntry) -> String {
        if let emailAddress = entry.account.emailAddress,
           !emailAddress.isEmpty,
           emailAddress != entry.account.displayName {
            return "\(entry.providerName) · \(emailAddress)"
        }
        return entry.providerName
    }

    private func disconnect(_ entry: AccountEntry) {
        disconnectingAccountID = entry.id

        Task {
            defer { disconnectingAccountID = nil }
            do {
                try await CloudStorageSyncService.shared.disconnect(
                    entry.account,
                    connections: connections
                )
            } catch {
                alertToast(error)
            }
        }
    }
}
