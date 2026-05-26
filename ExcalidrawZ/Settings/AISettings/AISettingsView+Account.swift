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
    @MainActor @ViewBuilder
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

    @MainActor @ViewBuilder
    var aiAccountRows: some View {
        HStack {
            Text(localizable: .settingsAIAccountProviderLabel)
            Spacer(minLength: 16)

            if let provider = aiUserInfo?.identity.provider {
                Text(provider)
                    .foregroundStyle(.secondary)
            } else if isLoadingAIUserInfo {
                Text(localizable: .generalLoading)
                    .foregroundStyle(.secondary)
            } else {
                Text(localizable: .settingsAIAccountLoadFailed)
                    .foregroundStyle(.secondary)
            }
        }

        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(localizable: .settingsAIAccountIDLabel)

            Spacer(minLength: 16)

            if let aiAccountID {
                Text(aiAccountID)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)

                Button {
                    copyAIAccountID(aiAccountID)
                } label: {
                    Text(didCopyAIAccountID ? String(localizable: .exportActionCopied) : String(localizable: .generalButtonCopy))
                }
                .buttonStyle(.borderless)
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
    }

    var aiAccountID: String? {
        guard let identity = aiUserInfo?.identity else { return nil }
        return (identity.userId ?? identity.id).uuidString
    }

    @MainActor
    func loadAIAccountInfoIfNeeded() async {
        guard AIChatAvailability.canUseAI else { return }
        guard aiUserInfo == nil, !isLoadingAIUserInfo else { return }
        await reloadAIAccountInfo()
    }

    @MainActor
    func reloadAIAccountInfo() async {
        guard AIChatAvailability.canUseAI else { return }
        guard !isLoadingAIUserInfo else { return }
        isLoadingAIUserInfo = true
        defer { isLoadingAIUserInfo = false }

        do {
            guard AIChatAvailability.canUseAI else { throw CancellationError() }
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
