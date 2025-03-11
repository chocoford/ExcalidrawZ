//
//  FeatureRow.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 1/21/25.
//

import SwiftUI
import AVKit

struct WhatsNewFeatureRow: View {
    
    var icon: AnyView
    var content: AnyView
    var overlayTrailing: AnyView
    
    init<Icon: View, Content: View, Trailing: View>(
        @ViewBuilder icon: () -> Icon,
        @ViewBuilder content: () -> Content,
        @ViewBuilder trailing: () -> Trailing = { EmptyView().frame(width: 0, height: 0) }
    ) {
        self.icon = AnyView(icon())
        self.content = AnyView(content())
        self.overlayTrailing = AnyView(trailing())
    }
    
    init<ImageView: View, Trailing: View>(
        title: LocalizedStringKey,
        description: LocalizedStringKey,
        @ViewBuilder icon: () -> ImageView,
        @ViewBuilder trailing: () -> Trailing = { EmptyView().frame(width: 0, height: 0) }
    ) {
        self.init {
            icon()
        } content: {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(description).font(.caption).foregroundStyle(.secondary)
            }
        } trailing: {
            trailing()
        }
    }
    
    init<Trailing: View>(
        title: LocalizedStringKey,
        description: LocalizedStringKey,
        icon: Image,
        @ViewBuilder trailing: @escaping () -> Trailing = { EmptyView().frame(width: 0, height: 0) }
    ) {
        self.init(title: title, description: description) {
            icon.resizable()
        } trailing: {
            trailing()
        }
    }
    
    // @State private var mediaPreviewImage: Image?
    @State private var overlayTrailingWidth: CGFloat = .zero
    
    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            icon
                .symbolRenderingMode(.multicolor)
                .scaledToFit()
                .frame(width: 68, height: 40, alignment: .center)
            
            content
            
            if overlayTrailingWidth > 0 {
                Rectangle()
                    .frame(width: overlayTrailingWidth, height: 1)
                    .opacity(0)
            }
        }
        .overlay(alignment: .trailing) {
            overlayTrailing
                .readWidth($overlayTrailingWidth)
        }
        
    }
}
