//
//  UpdateChecker.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 2023/1/1.
//
import Observation
#if os(macOS)
import Foundation
import Combine
import SwiftUI
import Sparkle

@Observable
final class UpdateChecker {
    @ObservationIgnored private var updaterSubscriptions: Set<AnyCancellable> = []
    var updater: SPUUpdater? = nil
    private(set) var canCheckForUpdates = false
    var automaticallyChecksForUpdates = false {
        didSet {
            if automaticallyChecksForUpdates != updater?.automaticallyChecksForUpdates {
                updater?.automaticallyChecksForUpdates = automaticallyChecksForUpdates
            }
        }
    }

    init() {}
    
    func assignUpdater(updater: SPUUpdater) {
        updaterSubscriptions.removeAll()
        self.updater = updater
        updater.publisher(for: \.canCheckForUpdates)
            .sink { [weak self] in self?.canCheckForUpdates = $0 }
            .store(in: &updaterSubscriptions)

        updater.publisher(for: \.automaticallyChecksForUpdates)
            .sink { [weak self] in self?.automaticallyChecksForUpdates = $0 }
            .store(in: &updaterSubscriptions)
    }
}
#endif
