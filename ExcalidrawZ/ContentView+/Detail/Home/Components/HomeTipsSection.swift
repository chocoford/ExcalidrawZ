//
//  HomeTipsSection.swift
//  ExcalidrawZ
//
//  Created by Chocoford on 8/29/25.
//

import SwiftUI

struct HomeTipsSection: View {
    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                Text("Tips").font(.headline)
                Spacer()
            }
            
            VStack {
                HStack {
                    Rectangle().fill(.secondary)
                    Rectangle().fill(.secondary)
                }
                .frame(height: 200)
            }
        }
    }
}


struct HomeTipItemView: View {
    
    
    
    var body: some View {
        
    }
}

#Preview {
    HomeTipsSection()
        .padding()
}
