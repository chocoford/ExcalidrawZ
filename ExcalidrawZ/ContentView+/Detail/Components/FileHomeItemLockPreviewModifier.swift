//
//  FileHomeItemLockPreviewModifier.swift
//  ExcalidrawZ
//
//  Created by Codex on 2026/05/29.
//

import SwiftUI
import ChocofordUI

struct FileHomeItemLockPreviewModifier: ViewModifier {
    let file: FileState.ActiveFile
    let iconSize: CGFloat
    var coverMode: FileHomeItemCoverMode = .standard

    func body(content: Content) -> some View {
        content.overlay {
            FilePreviewLockStateReader(file: file) { lockState in
                FileHomeItemLockPreview(
                    file: file,
                    iconSize: iconSize,
                    coverMode: coverMode,
                    lockState: lockState
                )
            }
            .allowsHitTesting(false)
        }
    }
}

private struct FileHomeItemLockPreview: View {
    @Environment(\.colorScheme) private var colorScheme

    let file: FileState.ActiveFile
    let iconSize: CGFloat
    let coverMode: FileHomeItemCoverMode
    let lockState: FileContentLockState?

    @State private var lockOverlayState: FileContentLockState?
    @State private var lockOverlayTask: Task<Void, Never>?
    @State private var observedLockState: FileContentLockState?

    init(
        file: FileState.ActiveFile,
        iconSize: CGFloat,
        coverMode: FileHomeItemCoverMode,
        lockState: FileContentLockState?
    ) {
        self.file = file
        self.iconSize = iconSize
        self.coverMode = coverMode
        self.lockState = lockState
        // A warm preview starts in its resting state, without an onAppear
        // write followed by another update just to initialize its overlay.
        self._lockOverlayState = State(initialValue: lockState == .locked ? .locked : nil)
        self._observedLockState = State(initialValue: lockState)
    }

    var body: some View {
        previewContent
            .overlay {
                if let lockOverlayState {
                    LockedFilePreviewPlaceholder(
                        lockState: lockOverlayState,
                        showsIcon: true,
                        iconSize: iconSize,
                        // The locked base already draws this background. Only
                        // an unlock transition needs it above a visible cover.
                        showsBackground: lockState != .locked
                    )
                    .transition(.opacity.combined(with: .scale(scale: 0.985)))
                    .allowsHitTesting(false)
                }
            }
            .animation(.smooth(duration: 0.26), value: lockOverlayState)
            .onAppear {
                guard observedLockState != lockState || lockOverlayState != restingOverlayState else { return }
                observedLockState = lockState
                setLockOverlayState(for: lockState, animated: false)
            }
            .watch(value: lockState) { newValue in
                guard observedLockState != newValue else { return }
                let shouldAnimate = observedLockState != nil
                observedLockState = newValue
                setLockOverlayState(for: newValue, animated: shouldAnimate)
            }
            .onDisappear {
                lockOverlayTask?.cancel()
            }
    }

    private var restingOverlayState: FileContentLockState? {
        lockState == .locked ? .locked : nil
    }

    @ViewBuilder
    private var previewContent: some View {
        if lockState == nil || lockState == .locked {
            LockedFilePreviewPlaceholder()
        } else if let lockState {
            coverContent(for: lockState)
            .allowsHitTesting(false)
        }
    }

    @ViewBuilder
    private func coverContent(for lockState: FileContentLockState) -> some View {
        switch coverMode {
            case .standard:
                ExcalidrawFileCover(
                    file: file,
                    refreshToken: coverRefreshToken(for: lockState),
                    allowsGeneration: true
                )
                .scaledToFill()
            case .cachedOnly:
                // CachedFileCover scales its image inside the proposed bounds.
                CachedFileCoverImage(file: file, colorScheme: colorScheme)
                    .id(FileItemPreviewCache.cacheKey(forID: file.canonicalID, colorScheme: colorScheme))
        }
    }

    @MainActor
    private func setLockOverlayState(
        for lockState: FileContentLockState?,
        animated: Bool
    ) {
        lockOverlayTask?.cancel()

        guard let lockState else {
            if lockOverlayState != nil { lockOverlayState = nil }
            return
        }

        guard animated else {
            let nextOverlayState: FileContentLockState? = lockState == .locked ? .locked : nil
            if lockOverlayState != nextOverlayState {
                var transaction = Transaction(animation: nil)
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    lockOverlayState = nextOverlayState
                }
            }
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

/// Diagnostic counterpart with the same resting cover and lock appearance,
/// without overlay state, animation tasks or appearance callbacks.
struct FileHomeItemStaticLockPreviewModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    let file: FileState.ActiveFile
    let iconSize: CGFloat

    func body(content: Content) -> some View {
        content.overlay {
            FilePreviewLockStateReader(file: file) { lockState in
                if lockState == nil || lockState == .locked {
                    LockedFilePreviewPlaceholder(
                        showsIcon: lockState == .locked,
                        iconSize: iconSize
                    )
                } else {
                    CachedFileCoverImage(file: file, colorScheme: colorScheme)
                        .id(FileItemPreviewCache.cacheKey(forID: file.canonicalID, colorScheme: colorScheme))
                }
            }
            .allowsHitTesting(false)
        }
    }
}

struct LockedFilePreviewPlaceholder: View {
    @Environment(\.colorScheme) private var colorScheme

    var lockState: FileContentLockState = .locked
    var showsIcon = false
    var iconSize: CGFloat = 34
    var showsBackground = true

    var body: some View {
        ZStack {
            if showsBackground {
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
            }

            if showsIcon {
                lockIcon
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
