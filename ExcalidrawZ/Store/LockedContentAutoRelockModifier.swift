//
//  LockedContentAutoRelockModifier.swift
//  ExcalidrawZ
//
//  Created by Codex on 2026/05/29.
//

import SwiftUI
import ChocofordUI

#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif

@MainActor
struct LockedContentAutoRelockModifier: ViewModifier {
    @Environment(\.scenePhase) private var scenePhase
    @Bindable var lockedContentState: LockedContentStateStore

#if os(macOS)
    @State private var eventMonitor: Any?
    @State private var screenLockObserver: NSObjectProtocol?
    @State private var sessionResignObserver: NSObjectProtocol?
    @State private var sessionBecomeActiveObserver: NSObjectProtocol?
#elseif os(iOS)
    @State private var protectedDataObserver: NSObjectProtocol?
    @State private var appInactivityRelockTask: Task<Void, Never>?
    @State private var appInactivityRelockGeneration = 0
#endif

    func body(content: Content) -> some View {
        content
            .onAppear {
                installActivityMonitorIfNeeded()
                installSystemLockObserverIfNeeded()
                lockedContentState.noteUserActivity()
            }
            .onDisappear {
                removeActivityMonitor()
                removeSystemLockObserver()
            }
            .watch(value: scenePhase) { newValue in
                handleScenePhaseChange(newValue)
            }
    }

    private func handleScenePhaseChange(_ scenePhase: ScenePhase) {
        switch scenePhase {
            case .active:
                lockedContentState.noteUserActivity()
                activatePendingAutomaticUnlockAfterAppReturn()

            case .inactive:
                break

            case .background:
#if os(iOS)
                relockForAppInactivity()
#endif

            @unknown default:
                break
        }
    }

    private func installActivityMonitorIfNeeded() {
#if os(macOS)
        guard eventMonitor == nil else { return }
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: activityEventMask) { event in
            Task { @MainActor in
                lockedContentState.noteUserActivity()
            }
            return event
        }
#endif
    }

    private func removeActivityMonitor() {
#if os(macOS)
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
        }
        eventMonitor = nil
#endif
    }

    private func installSystemLockObserverIfNeeded() {
#if os(macOS)
        guard screenLockObserver == nil else { return }
        screenLockObserver = DistributedNotificationCenter.default().addObserver(
            forName: .macOSScreenDidLock,
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor in
                await lockedContentState.relockForAppInactivity(
                    allowAutomaticUnlockOnNextActive: true
                )
            }
        }
        sessionResignObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.sessionDidResignActiveNotification,
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor in
                await lockedContentState.relockForAppInactivity(
                    allowAutomaticUnlockOnNextActive: true
                )
            }
        }
        sessionBecomeActiveObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.sessionDidBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor in
                lockedContentState.activatePendingAutomaticUnlockAfterAppReturn()
            }
        }
#elseif os(iOS)
        guard protectedDataObserver == nil else { return }
        protectedDataObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.protectedDataWillBecomeUnavailableNotification,
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor in
                relockForAppInactivity()
            }
        }
#endif
    }

    private func activatePendingAutomaticUnlockAfterAppReturn() {
#if os(iOS)
        let relockTask = appInactivityRelockTask
        let relockGeneration = appInactivityRelockGeneration
        Task { @MainActor in
            await relockTask?.value
            guard appInactivityRelockGeneration == relockGeneration else { return }
            appInactivityRelockTask = nil
            lockedContentState.activatePendingAutomaticUnlockAfterAppReturn()
        }
#else
        lockedContentState.activatePendingAutomaticUnlockAfterAppReturn()
#endif
    }

    private func relockForAppInactivity() {
#if os(iOS)
        appInactivityRelockGeneration += 1
        appInactivityRelockTask?.cancel()
        appInactivityRelockTask = Task { @MainActor in
            await lockedContentState.relockForAppInactivity(
                allowAutomaticUnlockOnNextActive: true
            )
        }
#endif
    }

    private func removeSystemLockObserver() {
#if os(macOS)
        if let screenLockObserver {
            DistributedNotificationCenter.default().removeObserver(screenLockObserver)
        }
        screenLockObserver = nil
        if let sessionResignObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(sessionResignObserver)
        }
        sessionResignObserver = nil
        if let sessionBecomeActiveObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(sessionBecomeActiveObserver)
        }
        sessionBecomeActiveObserver = nil
#elseif os(iOS)
        if let protectedDataObserver {
            NotificationCenter.default.removeObserver(protectedDataObserver)
        }
        protectedDataObserver = nil
        appInactivityRelockTask?.cancel()
        appInactivityRelockTask = nil
        appInactivityRelockGeneration += 1
#endif
    }

#if os(macOS)
    private var activityEventMask: NSEvent.EventTypeMask {
        [
            .keyDown,
            .flagsChanged,
            .leftMouseDown,
            .rightMouseDown,
            .otherMouseDown,
            .leftMouseDragged,
            .rightMouseDragged,
            .otherMouseDragged,
            .mouseMoved,
            .scrollWheel
        ]
    }
#endif
}

#if os(macOS)
private extension Notification.Name {
    static let macOSScreenDidLock = Notification.Name("com.apple.screenIsLocked")
}
#endif

extension View {
    func lockedContentAutoRelock(
        lockedContentState: LockedContentStateStore
    ) -> some View {
        modifier(
            LockedContentAutoRelockModifier(
                lockedContentState: lockedContentState
            )
        )
    }
}
