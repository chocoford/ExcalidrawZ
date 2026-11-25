//
//  AISettingsView+Account.swift
//  ExcalidrawZ
//
//  Created by Codex on 5/18/26.
//

import SwiftUI
import LLMKit

#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif

extension AISettingsView {
    @ViewBuilder
    var aiAccountHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(localizable: .settingsAIAccountTitle)
                .font(.headline)
                .foregroundStyle(.primary)

            Text(localizable: .settingsAIAccountSubtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    var aiAccountRows: some View {
        if usesCompactSettingsLayout {
            compactAIAccountProviderRow
            compactAIAccountIDRow
        } else {
            regularAIAccountProviderRow
            regularAIAccountIDRow
        }
    }

    @ViewBuilder
    var regularAIAccountProviderRow: some View {
        HStack {
            aiAccountProviderLabel
            Spacer(minLength: 16)

            aiAccountProviderValue
        }
    }

    @ViewBuilder
    var regularAIAccountIDRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            aiAccountIDLabel

            Spacer(minLength: 16)

            aiAccountIDValue
        }
    }

    @ViewBuilder
    var compactAIAccountProviderRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            aiAccountProviderLabel
            aiAccountProviderValue
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    var compactAIAccountIDRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            aiAccountIDLabel
            aiAccountIDValue
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    var aiAccountProviderLabel: some View {
        Text(localizable: .settingsAIAccountProviderLabel)
    }

    @ViewBuilder
    var aiAccountProviderValue: some View {
        if let provider = aiUserInfo?.identity.provider {
            Text(aiIdentityProviderDisplayName(provider))
                .foregroundStyle(.secondary)
        } else if isLoadingAIUserInfo {
            Text(localizable: .generalLoading)
                .foregroundStyle(.secondary)
        } else {
            Text(localizable: .settingsAIAccountLoadFailed)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    var aiAccountIDLabel: some View {
        Text(localizable: .settingsAIAccountIDLabel)
    }

    @ViewBuilder
    var aiAccountIDValue: some View {
        if let aiAccountID {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(aiAccountID)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Button {
                    copyAIAccountID(aiAccountID)
                } label: {
                    Text(didCopyAIAccountID ? String(localizable: .exportActionCopied) : String(localizable: .generalButtonCopy))
                }
                .buttonStyle(.borderless)
            }
        } else {
            HStack(spacing: 10) {
                Text(isLoadingAIUserInfo ? String(localizable: .generalLoading) : String(localizable: .settingsAIAccountLoadFailed))
                    .foregroundStyle(.secondary)

                if aiUserInfoLoadError != nil {
                    Button {
                        Task {
                            await reloadAIAccountInfo()
                        }
                    } label: {
                        Text(localizable: .generalButtonRetry)
                    }
                    .buttonStyle(.borderless)
                }
            }
        }
    }

    var aiAccountID: String? {
        guard let identity = aiUserInfo?.identity else { return nil }
        return (identity.userId ?? identity.id).uuidString
    }

    func aiIdentityProviderDisplayName(_ provider: String) -> String {
        switch provider {
            case "anonID":
                return "Anonymous"
            case "device":
                return "Device"
            case "appStore":
                return "App Store"
            case "weixinMiniProgram":
                return "Weixin Mini Program"
            default:
                return provider
                    .replacingOccurrences(of: "([a-z0-9])([A-Z])", with: "$1 $2", options: .regularExpression)
                    .capitalized
        }
    }

    @MainActor
    func loadAIAccountInfoIfNeeded() async {
        guard AIChatAvailability.canUseAI, !AIChatAvailability.usesDirectInference else { return }
        guard aiUserInfo == nil, !isLoadingAIUserInfo else { return }
        await reloadAIAccountInfo()
    }

    @MainActor
    func reloadAIAccountInfo() async {
        guard AIChatAvailability.canUseAI, !AIChatAvailability.usesDirectInference else { return }
        guard !isLoadingAIUserInfo else { return }
        isLoadingAIUserInfo = true
        defer { isLoadingAIUserInfo = false }

        do {
            guard AIChatAvailability.canUseAI, !AIChatAvailability.usesDirectInference else { throw CancellationError() }
            aiUserInfo = try await LLMClient.shared.getUserInfo()
            aiUserInfoLoadError = nil
        } catch is CancellationError {
        } catch {
            aiUserInfoLoadError = String(describing: error)
        }
    }

    @MainActor
    private func copyAIAccountID(_ accountID: String) {
#if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(accountID, forType: .string)
#elseif os(iOS)
        UIPasteboard.general.string = accountID
#endif
        didCopyAIAccountID = true

        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.5))
            if self.aiAccountID == accountID {
                didCopyAIAccountID = false
            }
        }
    }
}
