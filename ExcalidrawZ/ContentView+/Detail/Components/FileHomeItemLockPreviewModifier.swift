//
//  FileHomeItemLockPreviewModifier.swift
//  ExcalidrawZ
//
//  Created by Codex on 2026/05/29.
//

import SwiftUI
import ChocofordUI

struct FileHomeItemLockPreviewModifier: ViewModifier {
    @EnvironmentObject private var lockedContentState: LockedContentStateStore

    let file: FileState.ActiveFile
    let iconSize: CGFloat

    @State private var lockOverlayState: FileContentLockState?
    @State private var lockOverlayTask: Task<Void, Never>?
    @State private var hasResolvedLockState = false

    func body(content: Content) -> some View {
        let lockState = lockedContentState.previewLockState(for: file)

        return content
            .overlay {
                previewContent(for: lockState)
                    .allowsHitTesting(false)
            }
            .overlay {
                if let lockOverlayState {
                    LockedFilePreviewPlaceholder(
                        lockState: lockOverlayState,
                        showsIcon: true,
                        iconSize: iconSize
                    )
                    .transition(.opacity.combined(with: .scale(scale: 0.985)))
                    .allowsHitTesting(false)
                }
            }
            .animation(.smooth(duration: 0.26), value: lockOverlayState)
            .task(id: file.id) {
                guard lockedContentState.previewLockState(for: file) == nil else { return }
                await lockedContentState.refresh(file: file)
            }
            .onAppear {
                hasResolvedLockState = lockState != nil
                setLockOverlayState(for: lockState, animated: false)
            }
            .watch(value: lockState) { newValue in
                let shouldAnimate = hasResolvedLockState
                hasResolvedLockState = newValue != nil
                setLockOverlayState(for: newValue, animated: shouldAnimate)
            }
            .onDisappear {
                lockOverlayTask?.cancel()
            }
    }

    @ViewBuilder
    private func previewContent(for lockState: FileContentLockState?) -> some View {
        if lockState == .locked {
            LockedFilePreviewPlaceholder()
        } else if let lockState {
            ExcalidrawFileCover(
                file: file,
                refreshToken: coverRefreshToken(for: lockState),
                allowsGeneration: true
            )
            .scaledToFill()
            .allowsHitTesting(false)
        } else {
            LockedFilePreviewPlaceholder()
        }
    }

    @MainActor
    private func setLockOverlayState(
        for lockState: FileContentLockState?,
        animated: Bool
    ) {
        lockOverlayTask?.cancel()

        guard let lockState else {
            lockOverlayState = nil
            return
        }

        guard animated else {
            lockOverlayState = lockState == .locked ? .locked : nil
            return
        }

        switch lockState {
            case .locked:
                lockOverlayTask = Task { @MainActor in
                    withAnimation(.smooth(duration: 0.18)) {
                        lockOverlayState = .temporarilyUnlocked
                    }
                    try? await Task.sleep(nanoseconds: 220_000_000)
                    guard !Task.isCancelled else { return }
                    withAnimation(.smooth(duration: 0.24)) {
                        lockOverlayState = .locked
                    }
                }

            case .temporarilyUnlocked, .plaintext:
                lockOverlayTask = Task { @MainActor in
                    withAnimation(.smooth(duration: 0.18)) {
                        lockOverlayState = .temporarilyUnlocked
                    }
                    try? await Task.sleep(nanoseconds: 420_000_000)
                    guard !Task.isCancelled else { return }
                    withAnimation(.smooth(duration: 0.28)) {
                        lockOverlayState = nil
                    }
                }
        }
    }

    private func coverRefreshToken(for lockState: FileContentLockState) -> String {
        switch lockState {
            case .plaintext:
                "plaintext"
            case .locked:
                "locked"
            case .temporarilyUnlocked:
                "temporarilyUnlocked"
        }
    }
}

struct LockedFilePreviewPlaceholder: View {
    @Environment(\.colorScheme) private var colorScheme

    var lockState: FileContentLockState = .locked
    var showsIcon = false
    var iconSize: CGFloat = 34

    var body: some View {
        ZStack {
            Rectangle()
                .fill(baseColor)

            Rectangle()
                .fill(.ultraThickMaterial)

            LinearGradient(
                colors: [
                    .clear,
                    Color.black.opacity(colorScheme == .dark ? 0.16 : 0.08)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            if showsIcon {
                lockIcon
            }
        }
    }

    private var baseColor: Color {
        colorScheme == .dark
        ? Color(red: 0.06, green: 0.065, blue: 0.075)
        : Color(red: 0.92, green: 0.92, blue: 0.94)
    }

    @ViewBuilder
    private var lockIcon: some View {
        let icon = Image(systemName: lockState == .locked ? LockedContentSymbols.lockShield : LockedContentSymbols.keyShield)
            .font(.system(size: iconSize, weight: .semibold))
            .foregroundStyle(.secondary)
            .symbolRenderingMode(.hierarchical)

        if #available(macOS 14.0, iOS 17.0, *) {
            icon
                .contentTransition(.symbolEffect(.replace))
        } else {
            icon
        }
    }
}

struct UnlockedFileCoverBadge: View {
    @Environment(\.colorScheme) private var colorScheme

    let iconSize: CGFloat

    var body: some View {
        Image(systemName: LockedContentSymbols.keyShield)
            .font(.system(size: symbolSize, weight: .semibold))
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(Color.accentColor)
            .frame(width: badgeSize, height: badgeSize)
            .background {
                Circle()
                    .fill(.regularMaterial)
            }
            .overlay {
                Circle()
                    .strokeBorder(Color.white.opacity(colorScheme == .dark ? 0.18 : 0.42), lineWidth: 0.75)
            }
            .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.3 : 0.14), radius: 7, y: 3)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    private var badgeSize: CGFloat {
        max(22, min(32, iconSize * 0.82))
    }

    private var symbolSize: CGFloat {
        badgeSize * 0.56
    }
}
