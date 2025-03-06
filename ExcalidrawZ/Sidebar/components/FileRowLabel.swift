//
//  FileRowLabel.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 3/5/25.
//

import SwiftUI

struct FileRowLabel: View {
    var name: String
    var updatedAt: Date
    
    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                Text(name)
            }
            .foregroundColor(.secondary)
            .font(.title3)
            .lineLimit(1)
            .padding(.bottom, 4)

            HStack {
                Text(updatedAt.formatted())
                    .font(.footnote)
                    .layoutPriority(1)
                Spacer()
            }
        }
        .contentShape(Rectangle())
    }
}
