//
//  HomeFolderItemView.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 8/3/25.
//

import SwiftUI
import ChocofordUI

struct HomeFolderItemView: View {
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject var fileState: FileState

    var isSelected: Bool
    var name: String
    var itemsCount: Int
    
    @State private var isHovered = false
    
    var body: some View {
        HStack(spacing: 10) {
            Image(systemSymbol: .folderFill)
                .resizable()
                .scaledToFit()
                .frame(height: 24)
                .foregroundStyle(Color(red: 12/255.0, green: 157/255.0, blue: 229/255.0))
            
            VStack(alignment: .leading) {
                Text(name)
                    .font(.headline)
                    .lineLimit(1)
                
                Text("\(itemsCount) items")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
                   
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .background {
            ZStack {
                if #available(macOS 26.0, iOS 26.0, *) {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(
                            colorScheme == .light
                            ? AnyShapeStyle(HierarchicalShapeStyle.secondary)
                            : AnyShapeStyle(Color.clear)
                        )
                        .stroke(
                            isSelected
                            ? AnyShapeStyle(Color.accentColor)
                            : AnyShapeStyle(SeparatorShapeStyle())
                        )
                        .glassEffect(.clear, in: .rect(cornerRadius: 12))
                        .shadow(
                            color: colorScheme == .light
                            ? Color.gray.opacity(0.33)
                            : Color.black.opacity(0.33),
                            radius: isHovered
                            ? colorScheme == .light ? 2 : 6
                            : 0
                        )
                    
                } else {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(.background)
                        .shadow(
                            color: colorScheme == .light
                            ? Color.gray.opacity(0.2)
                            : Color.black.opacity(0.2),
                            radius: isHovered ? 4 : 0
                        )
                    
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(
                            isSelected
                            ? AnyShapeStyle(Color.accentColor)
                            : AnyShapeStyle(SeparatorShapeStyle())
                        )
                }
            }
            
        }
        .animation(.smooth(duration: 0.2), value: isHovered)
    }
}
