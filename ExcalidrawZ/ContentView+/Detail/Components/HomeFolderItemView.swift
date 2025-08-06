//
//  HomeFolderItemView.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 8/3/25.
//

import SwiftUI
import ChocofordUI

struct HomeFolderItemView: View {
    @EnvironmentObject var fileState: FileState

    var isSelected: Bool
    var name: String
    var itemsCount: Int
    
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
                
                Text("\(itemsCount) items")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
                   
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background {
            RoundedRectangle(cornerRadius: 12)
                .fill(.background)
                .shadow(color: Color.gray.opacity(0.2), radius: 4)
            
            RoundedRectangle(cornerRadius: 12)
                .stroke(
                    isSelected
                    ? AnyShapeStyle(Color.accentColor)
                    : AnyShapeStyle(SeparatorShapeStyle())
                )
            
        }
        .contentShape(Rectangle())
    }
}
