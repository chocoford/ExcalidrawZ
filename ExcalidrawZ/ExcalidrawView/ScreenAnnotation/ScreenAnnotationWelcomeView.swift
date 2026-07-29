#if os(macOS)
import AppKit
import CoreGraphics
import SwiftUI

import ChocofordUI

@MainActor
enum ScreenAnnotationPermissionState {
    static var hasScreenCapturePermission: Bool {
        CGPreflightScreenCaptureAccess()
    }

    static var shouldPresent: Bool {
        !hasScreenCapturePermission
    }
}

struct ScreenAnnotationWelcomeView: View {
    let onClose: () -> Void
    let onReady: () -> Void
    let onOpenPermissionSettings: () -> Void

    @State private var hasPermission =
        ScreenAnnotationPermissionState.hasScreenCapturePermission

    var body: some View {
        VStack(spacing: 0) {
            header

            Spacer(minLength: 24)

            hero

            permissionSection
                .padding(.top, 28)

            Spacer(minLength: 28)

            getStartedButton
        }
        .padding(28)
        .frame(width: 560, height: 520)
        .background(Color.windowBackgroundColor)
        .onReceive(
            NotificationCenter.default.publisher(
                for: NSApplication.didBecomeActiveNotification
            )
        ) { _ in
            refreshPermission()
        }
    }

    private var header: some View {
        HStack {
            Button(action: onClose) {
                Label(
                    String(localizable: .generalButtonClose),
                    systemImage: "xmark"
                )
                .labelStyle(.iconOnly)
            }
            .modernButtonStyle(style: .glass, size: .extraLarge, shape: .circle)

            Spacer()
        }
    }

    private var hero: some View {
        VStack(spacing: 16) {
            Image(systemName: "macwindow.and.pointer.arrow")
                .font(.system(size: 42, weight: .medium))
                .foregroundStyle(.tint)
                .frame(width: 88, height: 88)
                .background(.tint.opacity(0.12), in: Circle())

            VStack(spacing: 8) {
                Text(localizable: .screenAnnotationTitle)
                    .font(.largeTitle.weight(.semibold))

                Text(localizable: .whatsNewScreenAnnotationDescription)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 440)
            }
        }
    }

    private var permissionSection: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(
                systemName: hasPermission
                    ? "checkmark.shield.fill"
                    : "rectangle.on.rectangle.badge.gearshape"
            )
            .font(.system(size: 22, weight: .medium))
            .foregroundStyle(hasPermission ? Color.green : Color.accentColor)
            .frame(width: 28)

            VStack(alignment: .leading, spacing: 5) {
                Text(localizable: .screenAnnotationPermissionTitle)
                    .font(.headline)

                Text(localizable: .screenAnnotationPermissionMessage)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(16)
        .background(.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }

    private var getStartedButton: some View {
        Button(
            action: hasPermission ? onReady : onOpenPermissionSettings
        ) {
            Label(
                hasPermission
                    ? String(localizable: .screenAnnotationGetStarted)
                    : String(localizable: .generalButtonSettings),
                systemImage: hasPermission ? "arrow.right" : "gear"
            )
                .frame(maxWidth: .infinity)
        }
        .modernButtonStyle(
            style: .glassProminent,
            size: .extraLarge,
            shape: .modern
        )
    }

    private func refreshPermission() {
        hasPermission =
            ScreenAnnotationPermissionState.hasScreenCapturePermission
    }
}
#endif
