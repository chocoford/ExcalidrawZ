//
//  AIChatWelcomeView.swift
//  ExcalidrawZ
//

import SwiftUI
import ChocofordUI
import SFSafeSymbols

struct AIChatWelcomeView: View {
    var onGetStarted: () -> Void
    private let buttonTitle: String
    private let buttonCaption: String
    private let buttonURL: URL?
    private let requiresEnableConfirmation: Bool

    @State private var isStarting = false
    @State private var isConfirmingEnable = false

    init(
        buttonTitle: String = String(localizable: .aiChatWelcomeButtonGetStarted),
        buttonCaption: String = String(localizable: .aiChatWelcomeGetStartedCaption),
        buttonURL: URL? = nil,
        requiresEnableConfirmation: Bool = false,
        onGetStarted: @escaping () -> Void
    ) {
        self.buttonTitle = buttonTitle
        self.buttonCaption = buttonCaption
        self.buttonURL = buttonURL
        self.requiresEnableConfirmation = requiresEnableConfirmation
        self.onGetStarted = onGetStarted
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(spacing: 12) {
                    AIIdentityIcon(size: 40)
                        .accessibilityHidden(true)

                    Text(localizable: .aiChatTitle)
                        .font(.title2.weight(.semibold))
                }

                getStartedButton

                DisclosureGroup {
                    featureList
                        .padding(.top, 12)
                } label: {
                    Text(localizable: .aiChatWelcomeCaption)
                        .font(.callout.weight(.medium))
                }
                .accessibilityIdentifier("aiChatWelcomeDetails")
            }
            .frame(maxWidth: 420, alignment: .leading)
            .padding(20)
            .frame(maxWidth: .infinity)
        }
        .accessibilityIdentifier("aiChatWelcomeScrollView")
        .allowsHitTesting(!isStarting)
        .sheet(isPresented: $isConfirmingEnable) {
            AIEnableConsentSheet(onEnable: start)
        }
    }

    private var getStartedButton: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let buttonURL {
                Link(destination: buttonURL) {
                    getStartedButtonLabel
                }
                .modernButtonStyle(style: .glassProminent, size: .extraLarge, shape: .modern)
                .keyboardShortcut(.defaultAction)
            } else {
                Button {
                    if requiresEnableConfirmation {
                        isConfirmingEnable = true
                    } else {
                        start()
                    }
                } label: {
                    getStartedButtonLabel
                }
                .modernButtonStyle(style: .glassProminent, size: .extraLarge, shape: .modern)
                .keyboardShortcut(.defaultAction)
                .disabled(isStarting)
                .accessibilityIdentifier("aiChatWelcomePrimaryAction")
            }

            Text(buttonCaption)
                .font(.callout)
                .foregroundStyle(buttonURL == nil ? .secondary : .primary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var getStartedButtonLabel: some View {
        HStack(spacing: 8) {
            Text(buttonTitle)
                .fontWeight(.semibold)
                .fixedSize(horizontal: false, vertical: true)
            Image(systemSymbol: .arrowRight)
                .font(.callout.weight(.semibold))
                .accessibilityHidden(true)
        }
        .frame(maxWidth: .infinity)
    }

    private var featureList: some View {
        VStack(alignment: .leading, spacing: 16) {
            feature(
                title: String(localizable: .aiChatWelcomeFeatureDrawTitle),
                message: String(localizable: .aiChatWelcomeFeatureDrawSubtitle)
            )
            feature(
                title: String(localizable: .aiChatWelcomeFeatureReadTitle),
                message: String(localizable: .aiChatWelcomeFeatureReadSubtitle)
            )
            feature(
                title: String(localizable: .aiChatWelcomeFeatureBrowseTitle),
                message: String(localizable: .aiChatWelcomeFeatureBrowseSubtitle)
            )
            feature(
                title: String(localizable: .aiChatWelcomeFeatureRevertTitle),
                message: String(localizable: .aiChatWelcomeFeatureRevertSubtitle)
            )
            .accessibilityIdentifier("aiChatWelcomeRevertFeature")
        }
    }

    private func feature(title: String, message: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.callout.weight(.semibold))
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .combine)
    }

    @MainActor
    private func start() {
        guard !isStarting else { return }
        isStarting = true
        onGetStarted()
    }
}

#if DEBUG
#Preview {
    AIChatWelcomeView(onGetStarted: {})
        .frame(width: 280, height: 600)
}
#endif
