//
//  UpdateChecker.swift
//  ExcaliDrawZ
//
//  Created by Dove Zachary on 2023/1/1.
//

import Foundation
import SwiftUI
import Sparkle

final class UpdateChecker: ObservableObject {
    @Published var canCheckForUpdates = false

    init(updater: SPUUpdater) {
        updater.publisher(for: \.canCheckForUpdates)
            .assign(to: &$canCheckForUpdates)
    }
}
