//
//  UpdateChecker.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 2023/1/1.
//
#if os(macOS)
import Foundation
import SwiftUI
import Sparkle

final class UpdateChecker: ObservableObject {
    var updater: SPUUpdater? = nil
    @Published var canCheckForUpdates = false {
        didSet {
            if canCheckForUpdates != updater?.automaticallyChecksForUpdates {
                updater?.automaticallyChecksForUpdates = canCheckForUpdates
            }
        }
    }

    init() {}
    
    func assignUpdater(updater: SPUUpdater) {
        self.updater = updater
        updater.publisher(for: \.canCheckForUpdates)
            .assign(to: &$canCheckForUpdates)
        
    }
}
#endif
