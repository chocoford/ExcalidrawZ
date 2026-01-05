//
//  FileHistoryTips.swift
//  ExcalidrawZ
//
//  Created by Chocoford on 8/30/25.
//

import SwiftUI

import MarkdownUI

extension HomeTipItemView {
    static let fileHistory = HomeTipItemView(
        title: .localizable(.tipsFileHistoryOverviewTitle),
        message: .localizable(.tipsFileHistoryOverviewDescription),
        icon: {
            if #available(macOS 15.0, iOS 18.0, *) {
                .clockArrowTriangleheadCounterclockwiseRotate90
            } else {
                .clockArrowCirclepath
            }
        }()
    ) {
        FileHistoryTipsDetail()
    }
}

struct FileHistoryTipsDetail: View {
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        TipDetailContainer {
            Text(.localizable(.tipsFileHistoryDetailTitle))
                .font(.title)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            AutoContainVideoPlayer(
                url: URL(string: "https://pub-2983ae3d3c894bd08530707492e919db.r2.dev/ExcalidrawZ File History guide.mov")!
            )
            .clipShape(RoundedRectangle(cornerRadius: 30))
            
            Markdown(String(localizable: .tipsFileHistoryDetailContent))
        }
    }
}
