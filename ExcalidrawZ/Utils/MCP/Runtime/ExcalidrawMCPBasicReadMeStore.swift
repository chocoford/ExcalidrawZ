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
        guard let readMe = UserDefaults.standard.string(forKey: overrideDefaultsKey),
              !readMe.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return defaultReadMe
        }
        return readMe
    }

    static func save(_ readMe: String) {
        guard !readMe.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
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
