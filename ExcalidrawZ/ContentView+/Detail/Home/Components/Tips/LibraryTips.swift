//
//  LibraryTips.swift
//  ExcalidrawZ
//
//  Created by Chocoford on 8/30/25.
//

import SwiftUI
import MarkdownUI

extension HomeTipItemView {
    static let library = HomeTipItemView(
        title: .localizable(.tipsLibraryOverviewTitle),
        message: .localizable(.tipsLibraryOverviewDescription),
        icon: .book
    ) {
        LibraryTipsDetail()
    }
}


struct LibraryTipsDetail: View {
    var body: some View {
        TipDetailContainer {
            
            Text(localizable: .tipsLibraryDetailTitle).font(.title)
            
            Text(localizable: .tipsLibraryDetailLibraryDescription)
            
            
            Text(localizable: .tipsLibraryDetailImportUseTitle).font(.headline)
            
            AutoContainVideoPlayer(
//                url: Bundle.main.url(
//                    forResource: "ExcalidrawZ - Library import",
//                    withExtension: "mov"
//                )!
                url: URL(string: "https://pub-2983ae3d3c894bd08530707492e919db.r2.dev/ExcalidrawZ - Library import.mov")!
            )
            .clipShape(RoundedRectangle(cornerRadius: 30))
            
            Markdown(String(localizable: .tipsLibraryDetailImportUseContent))
            
            
            Text(localizable: .tipsLibraryDetailAddExportTitle).font(.headline)
            
            AutoContainVideoPlayer(
//                url: Bundle.main.url(
//                    forResource: "ExcalidrawZ - Library Add&Export",
//                    withExtension: "mov"
//                )!
                url: URL(string: "https://pub-2983ae3d3c894bd08530707492e919db.r2.dev/ExcalidrawZ - Library Add&Export.mov")!
            )
            .clipShape(RoundedRectangle(cornerRadius: 30))
            
            Markdown(String(localizable: .tipsLibraryDetailAddExportContent))
        }
    }
}
