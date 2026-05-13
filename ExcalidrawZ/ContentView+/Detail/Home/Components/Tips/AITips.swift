//
//  AITips.swift
//  ExcalidrawZ
//
//  Created by Codex on 5/11/26.
//

import SwiftUI
import MarkdownUI

extension HomeTipItemView {
    static let ai = HomeTipItemView(
        title: String(localizable: .tipsAIOverviewTitle),
        message: String(localizable: .tipsAIOverviewDescription),
        icon: .sparkles
    ) {
        AITipsDetail()
    }
}

struct AITipsDetail: View {
    var body: some View {
        TipDetailContainer(spacing: 24) {
            VStack(alignment: .leading, spacing: 6) {
                Text(localizable: .tipsAIDetailTitle)
                    .font(.title)

                Text(localizable: .tipsAIDetailDescription)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Markdown(String(localizable: .tipsAIDetailContent))
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
