//
//  ExcalidrawMCPBasicReadMeStore.swift
//  ExcalidrawZ
//
//  Created by Codex on 8/16/26.
//

import Foundation

enum ExcalidrawMCPBasicReadMeStore {
    private static let overrideDefaultsKey = "ExcalidrawMCPBasicReadMeOverride"

    static var defaultReadMe: String {
        ExcalidrawMCPUpstreamRecall.cheatSheet
    }

    static var currentReadMe: String {
        UserDefaults.standard.string(forKey: overrideDefaultsKey) ?? defaultReadMe
    }

    static func save(_ readMe: String) {
        guard readMe != defaultReadMe else {
            restoreDefault()
            return
        }

        UserDefaults.standard.set(readMe, forKey: overrideDefaultsKey)
    }

    static func restoreDefault() {
        UserDefaults.standard.removeObject(forKey: overrideDefaultsKey)
    }
}
