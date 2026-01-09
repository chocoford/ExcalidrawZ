//
//  ShareTips.swift
//  ExcalidrawZ
//
//  Created by Chocoford on 9/1/25.
//

import SwiftUI
import AVKit

import MarkdownUI

extension HomeTipItemView {
    static let share = HomeTipItemView(
        title: .localizable(.tipsShareOverviewTitle),
        message: .localizable(.tipsShareOverviewDescription),
        icon: .squareAndArrowUp
    ) {
        ShareTipsDetail()
    }
}

struct ShareTipsDetail: View {
    var body: some View {
        TipDetailContainer(spacing: 24) {
            VStack(alignment: .leading, spacing: 6) {
                Text(.localizable(.tipsShareDetailTitle))
                    .font(.title)
                
                Text(.localizable(.tipsShareDetailDescription))
            }
            
            
            VStack(alignment: .leading, spacing: 10) {
                Text(.localizable(.tipsShareDetailExportImageTitle))
                    .font(.title3.bold())
                
                AutoContainVideoPlayer(
                    url: URL(string: "https://pub-2983ae3d3c894bd08530707492e919db.r2.dev/ExcalidrawZ - Share image.mov")!,
                    baseAxis: .horizontal
                )
                .clipShape(RoundedRectangle(cornerRadius: 30))
                
                Markdown(String(localizable: .tipsShareDetailExportImageContent))
            }
            
            
            VStack(alignment: .leading, spacing: 10) {
                Text(.localizable(.tipsShareDetailExportFileTitle))
                    .font(.title3.bold())
                
                AutoContainVideoPlayer(
                    url: URL(string: "https://pub-2983ae3d3c894bd08530707492e919db.r2.dev/ExcalidrawZ - Share file.mov")!,
                    baseAxis: .horizontal
                )
                .clipShape(RoundedRectangle(cornerRadius: 30))
                
                
                Markdown(String(localizable: .tipsShareDetailExportFileContent))
            }
            
            
            VStack(alignment: .leading, spacing: 10) {
                Text(.localizable(.tipsShareDetailExportPDFTitle))
                    .font(.title3.bold())
                
                AutoContainVideoPlayer(
                    url: URL(string: "https://pub-2983ae3d3c894bd08530707492e919db.r2.dev/ExcalidrawZ - Share PDF.mov")!,
                    baseAxis: .horizontal
                )
                .clipShape(RoundedRectangle(cornerRadius: 30))
                
                Markdown(String(localizable: .tipsShareDetailExportPDFContent))
            }
            
            VStack(alignment: .leading, spacing: 10) {
                Text(.localizable(.tipsShareDetailArchiveTitle))
                    .font(.title3.bold())
                
                Image("ExcalidrawZ - Share archive 1x")
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 30))
                
                Markdown(String(localizable: .tipsShareDetailArchiveContent))
            }
        }
    }
}

