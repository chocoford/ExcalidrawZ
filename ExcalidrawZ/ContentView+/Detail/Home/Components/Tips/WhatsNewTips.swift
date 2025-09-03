//
//  WhatsNewTips.swift
//  ExcalidrawZ
//
//  Created by Chocoford on 8/30/25.
//

import SwiftUI

extension HomeTipItemView {
    static let whatsNew = HomeTipItemView(
        title: .localizable(.tipsWhatsNewOverviewTitle),
        message: "ExcalidrawZ \( Bundle.main.infoDictionary!["CFBundleShortVersionString"] as? String ?? "")",
        image: Image("AppIcon-macOS")
    ) {
        WhatsNewView()
    }
}
