//
//  AIEnableConsentSheet.swift
//  ExcalidrawZ
//

import SwiftUI
import ChocofordUI
import SFSafeSymbols

@MainActor
struct AIEnableConsentSheet: View {
    @Environment(\.containerHorizontalSizeClass) private var containerHorizontalSizeClass
    @Environment(\.dismiss) private var dismiss

    var mode: AIInferenceBillingMode = .platform
    var onEnable: () -> Void

    @State private var hasAcceptedTerms = false

    var body: some View {
        ZStack {
            if isCompactIOS {
                compactBody
            } else {
                regularBody
            }
        }
#if os(macOS)
        .frame(width: 640)
#endif
    }

    private var regularBody: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 22) {
                content
            }
            .padding(24)

            HStack(spacing: 10) {
                Spacer()

                footerButtons
            }
            .padding(.horizontal, 24)
            .padding(.top, 10)
            .padding(.bottom, 22)
        }
    }

    private var compactBody: some View {
        ScrollView {
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: contentSpacing) {
                    content
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, horizontalPadding)
                .padding(.top, topPadding)
                .padding(.bottom, 12)

                Spacer(minLength: 18)

                enableButtonRow
                    .padding(.horizontal, horizontalPadding)
                    .padding(.bottom, bottomPadding)
            }
        }
    }

    private var isDirect: Bool { mode == .byok && AIInferenceBillingState.shared.integrationMode == .basic }

    private var isCompactIOS: Bool {
#if os(iOS)
        containerHorizontalSizeClass == .compact
#else
        false
#endif
    }

    private var contentSpacing: CGFloat {
        isCompactIOS ? 16 : 22
    }

    private var rowSpacing: CGFloat {
        isCompactIOS ? 10 : 14
    }

    private var horizontalPadding: CGFloat {
        isCompactIOS ? 20 : 24
    }

    private var topPadding: CGFloat {
        isCompactIOS ? 18 : 24
    }

    private var bottomPadding: CGFloat {
        isCompactIOS ? 20 : 22
    }

    private var identityIconSize: CGFloat {
        isCompactIOS ? 42 : 48
    }

    @ViewBuilder
    private var content: some View {
        header

        consentList

        policyLinks

        agreementToggle
    }

    private var cancelButton: some View {
        Button {
            dismiss()
        } label: {
            Text(localizable: .generalButtonCancel)
        }
        .keyboardShortcut(.cancelAction)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            if mode == .byok {
                Image(systemSymbol: .key)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: identityIconSize, height: identityIconSize)
                    .background(Color.accentColor.opacity(0.10), in: RoundedRectangle(cornerRadius: 12))
                    .padding(.bottom, 2)
            } else {
                AIIdentityIcon(size: identityIconSize)
                    .padding(.bottom, 2)
            }

            Text(.localizable(mode == .byok ? .aiBYOKEnableTitle : .aiPlatformEnableTitle))
                .font(.title2.weight(.semibold))

            Text(isDirect ? String(localized: "AI.Direct.consentSubtitle")
                 : String(localizable: mode == .byok ? .aiBYOKEnableSubtitle : .aiChatEnableConsentSubtitle))
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var consentList: some View {
        VStack(alignment: .leading, spacing: rowSpacing) {
            if mode == .byok {
                consentRow(
                    icon: .key,
                    title: String(localizable: .aiBYOKConsentKeyTitle),
                    message: isDirect ? String(localized: "AI.Direct.consentKey") : String(localizable: .aiBYOKConsentKeyMessage)
                )
                consentRow(
                    icon: .cloud,
                    title: String(localizable: .aiBYOKConsentDataTitle),
                    message: isDirect ? String(localized: "AI.Direct.consentData") : String(localizable: .aiBYOKConsentDataMessage)
                )
                consentRow(
                    icon: .creditcard,
                    title: String(localizable: .aiBYOKConsentBillingTitle),
                    message: isDirect ? String(localized: "AI.Direct.noCredits") : String(localizable: .aiBYOKConsentBillingMessage)
                )
                consentRow(
                    icon: .lock,
                    title: String(localizable: .aiBYOKConsentProviderTitle),
                    message: String(localizable: .aiBYOKConsentProviderMessage)
                )
            } else {
                consentRow(
                    icon: .cloud,
                    title: String(localizable: .aiChatEnableConsentCloudTitle),
                    message: String(localizable: .aiChatEnableConsentCloudMessage)
                )
                consentRow(
                    icon: .docTextMagnifyingglass,
                    title: String(localizable: .aiChatEnableConsentDataTitle),
                    message: String(localizable: .aiChatEnableConsentDataMessage)
                )
                consentRow(
                    icon: .lock,
                    title: String(localizable: .aiChatEnableConsentSensitiveTitle),
                    message: String(localizable: .aiChatEnableConsentSensitiveMessage)
                )
                consentRow(
                    icon: .gearshape,
                    title: String(localizable: .aiChatEnableConsentProviderTitle),
                    message: String(localizable: .aiChatEnableConsentProviderMessage)
                )
            }
        }
    }

    private var agreementToggle: some View {
        Toggle(isOn: $hasAcceptedTerms) {
            Text(.localizable(mode == .byok ? .aiBYOKConsentAgreement : .aiPlatformConsentAgreement))
                .font(.callout.weight(.medium))
                .fixedSize(horizontal: false, vertical: true)
        }
#if os(macOS)
        .toggleStyle(.checkbox)
#endif
    }

    private var enableButtonRow: some View {
        VStack(spacing: 10) {
            HStack {
                Spacer(minLength: 0)

                enableButton
            }

            cancelButton
        }
    }

    private var enableButton: some View {
        Button {
            enableService()
        } label: {
            Text(.localizable(mode == .byok ? .aiBYOKEnableButton : .aiPlatformEnableButton))
                .frame(maxWidth: isCompactIOS ? .infinity : nil)
        }
        .keyboardShortcut(.defaultAction)
        .modernButtonStyle(style: .glassProminent, size: .large, shape: .capsule)
        .frame(maxWidth: isCompactIOS ? .infinity : nil)
        .disabled(!hasAcceptedTerms)
    }

    @ViewBuilder
    private var footerButtons: some View {
        if #available(macOS 26.0, iOS 26.0, *) {
            GlassEffectContainer(spacing: 10) {
                footerButtonContent
            }
        } else {
            footerButtonContent
        }
    }

    private var footerButtonContent: some View {
        HStack(spacing: 10) {
            Button(.localizable(.generalButtonCancel)) {
                dismiss()
            }
            .keyboardShortcut(.cancelAction)
            .modernButtonStyle(style: .glass, size: .large, shape: .capsule)

            Button {
                enableService()
            } label: {
                Text(.localizable(mode == .byok ? .aiBYOKEnableButton : .aiPlatformEnableButton))
            }
            .keyboardShortcut(.defaultAction)
            .modernButtonStyle(style: .glassProminent, size: .large, shape: .capsule)
            .disabled(!hasAcceptedTerms)
        }
    }

    private func enableService() {
        guard hasAcceptedTerms else { return }
        dismiss()
        onEnable()
    }

    private func consentRow(
        icon: SFSymbol,
        title: String,
        message: String
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemSymbol: icon)
                .font(.body.weight(.semibold))
                .foregroundStyle(Color.accentColor)
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
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var policyLinks: some View {
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

#Preview {
    AIEnableConsentSheet {}
}
