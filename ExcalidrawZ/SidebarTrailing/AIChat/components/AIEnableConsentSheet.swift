//
//  AIEnableConsentSheet.swift
//  ExcalidrawZ
//

import SwiftUI
import ChocofordUI
import SFSafeSymbols

struct AIEnableConsentSheet: View {
    @Environment(\.dismiss) private var dismiss

    var onEnable: () -> Void

    @State private var hasAcceptedTerms = false

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 22) {
                header
                
                VStack(spacing: 14) {
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
                
                policyLinks
                
                Toggle(isOn: $hasAcceptedTerms) {
                    Text(localizable: .aiChatEnableConsentAgreement)
                        .font(.callout.weight(.medium))
                        .fixedSize(horizontal: false, vertical: true)
                }
#if os(macOS)
                .toggleStyle(.checkbox)
#endif
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
#if os(macOS)
        .frame(width: 640)
#endif
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            AIIdentityIcon(size: 48)
                .padding(.bottom, 2)

            Text(localizable: .aiChatEnableConfirmationTitle)
                .font(.title2.weight(.semibold))

            Text(localizable: .aiChatEnableConsentSubtitle)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
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
                dismiss()
                onEnable()
            } label: {
                Text(localizable: .aiChatEnableConfirmationButtonEnable)
            }
            .keyboardShortcut(.defaultAction)
            .modernButtonStyle(style: .glassProminent, size: .large, shape: .capsule)
            .disabled(!hasAcceptedTerms)
        }
    }
}

#Preview {
    AIEnableConsentSheet {}
}
