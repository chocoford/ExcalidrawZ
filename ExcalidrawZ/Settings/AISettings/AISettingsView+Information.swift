//
//  AISettingsView+Information.swift
//  ExcalidrawZ
//
//  Created by Codex on 5/26/26.
//

import SwiftUI
import SFSafeSymbols

extension AISettingsView {
    @MainActor @ViewBuilder
    var informationHeader: some View {
        settingsTabHeader {
            HStack(alignment: .top, spacing: 16) {
                Image(systemSymbol: .infoCircle)
                    .font(.title2)
                    .foregroundStyle(Color.accentColor)

                VStack(alignment: .leading, spacing: 6) {
                    Text(localizable: .settingsAIInformationTitle)
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(.primary)

                    Text(localizable: .settingsAIInformationSubtitle)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    @MainActor @ViewBuilder
    var aiInformationRows: some View {
        if !prefs.isAIEnabled {
            Toggle(isOn: aiEnabledBinding) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(localizable: .settingsAIEnableFeatureTitle)
                    Text(localizable: .settingsAIEnableFeatureHelp)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }

        aiInformationRow(
            icon: .cloud,
            title: String(localizable: .settingsAIInformationCloudTitle),
            message: String(localizable: .settingsAIInformationCloudMessage)
        )

        aiInformationRow(
            icon: .arrowUpDoc,
            title: String(localizable: .settingsAIInformationDataTitle),
            message: String(localizable: .settingsAIInformationDataMessage)
        )

        aiInformationRow(
            icon: .docTextMagnifyingglass,
            title: String(localizable: .settingsAIInformationFilesTitle),
            message: String(localizable: .settingsAIInformationFilesMessage)
        )

        aiInformationRow(
            icon: .gearshape,
            title: String(localizable: .settingsAIInformationProvidersTitle),
            message: String(localizable: .settingsAIInformationProvidersMessage)
        )

        aiInformationRow(
            icon: .sliderHorizontal3,
            title: String(localizable: .settingsAIInformationControlsTitle),
            message: String(localizable: .settingsAIInformationControlsMessage)
        )

        aiInformationRow(
            icon: .desktopcomputer,
            title: String(localizable: .settingsAIInformationLocalModelsTitle),
            message: String(localizable: .settingsAIInformationLocalModelsMessage)
        )

        aiInformationPolicyLinksRow
    }

    @MainActor
    private func aiInformationRow(
        icon: SFSymbol,
        title: String,
        message: String
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemSymbol: icon)
                .font(.body.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.body.weight(.semibold))

                Text(message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 3)
    }

    @MainActor
    private var aiInformationPolicyLinksRow: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemSymbol: .docTextMagnifyingglass)
                .font(.body.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 8) {
                Text(localizable: .settingsAIInformationPoliciesTitle)
                    .font(.body.weight(.semibold))

                Text(localizable: .settingsAIInformationPoliciesMessage)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 14) {
                    Link(
                        .localizable(.generalButtonPrivacyPolicy),
                        destination: URL(string: "https://excalidrawz.chocoford.com/privacy/")!
                    )

                    Link(
                        .localizable(.generalButtonTermsOfUse),
                        destination: URL(string: "https://excalidrawz.chocoford.com/terms/")!
                    )
                }
                .font(.callout.weight(.semibold))
            }
        }
        .padding(.vertical, 3)
    }
}
