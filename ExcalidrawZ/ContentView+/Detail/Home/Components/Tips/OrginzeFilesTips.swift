//
//  OrginzeFilesTips.swift
//  ExcalidrawZ
//
//  Created by Chocoford on 8/30/25.
//

import SwiftUI
import AVKit

import MarkdownUI

extension HomeTipItemView {
    static let orginzeFiles = HomeTipItemView(
        title: .localizable(.tipsOrganizeFilesOverviewTitle),
        message: .localizable(.tipsOrganizeFilesOverviewDescription),
        icon: .squareFillTextGrid1x2
    ) {
        OrginzeFilesTipsDetail()
    }
}

struct OrginzeFilesTipsDetail: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        TipDetailContainer {
            VStack(alignment: .leading, spacing: 20) {
                Text(localizable: .tipsOrganizeFilesDetailTitle)
                    .font(.title)
                
                Text(localizable: .tipsOrganizeFilesDetailDescription)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            AutoContainVideoPlayer(
                url: URL(string: "https://pub-2983ae3d3c894bd08530707492e919db.r2.dev/ExcalidrawZ - Organize files.mov")!,
            )
            .clipShape(RoundedRectangle(cornerRadius: 30))

            Markdown(String(localizable: .tipsOrganizeFilesDetailContent))
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
    
