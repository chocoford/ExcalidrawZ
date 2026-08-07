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
                Text("Connected Accounts")
            } footer: {
                Text("Disconnecting removes this account, its linked folders, and local caches from ExcalidrawZ. Files stored in the cloud are not deleted.")
            }
        }
        .navigationTitle("Connected Accounts")
        .task {
            await connections.refresh()
        }
        .alert(item: $disconnectRequest) { entry in
            Alert(
                title: Text("Disconnect Account?"),
                message: Text(
                    "Disconnect \(entry.account.displayName) from \(entry.providerName)? All linked folders for this account will be removed from ExcalidrawZ."
                ),
                primaryButton: .destructive(Text("Disconnect")) {
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
                Text("No Connected Accounts")
                    .font(.headline)
                Text("Connect a cloud storage provider from Linked Storage in the sidebar.")
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
                Button("Disconnect", role: .destructive) {
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
