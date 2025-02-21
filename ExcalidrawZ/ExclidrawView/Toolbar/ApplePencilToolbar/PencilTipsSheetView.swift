//
//  PencilTipsSheetView.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 2/21/25.
//

import SwiftUI

struct PencilTipsSheetView: View {
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(spacing: 16) {
            Text("Apple pencil connected")
                .font(.title)
            
            HStack(alignment: .top) {
                VStack {
                    Text("Select with finger")
                        .font(.headline)
                    
                    Text(
"""
• Drag with one finger to select
• Use two fingers to move or zoom the canvas
"""
                    )
                    .font(.callout)
                }
                .padding()
                .frame(maxWidth: .infinity)
                
                Divider()
                
                VStack {
                    Text("Move with finger")
                        .font(.headline)
                    
                    Text(
"""
• Use one finger to move the canvas
• Use two fingers to move or zoom the canvas
• Select with the dedicated tool
"""
                    )
                    .font(.callout)
                }
                .padding()
                .frame(maxWidth: .infinity)
            }
            
            Text("You can later change this in settings.")
                .foregroundStyle(.secondary)
                .font(.footnote)
            Button {
                dismiss()
            } label: {
                Text("Done")
                    .padding(.horizontal)
            }
            .buttonStyle(.borderedProminent)
        }
    }
}

#Preview {
    Color.clear
        .sheet(isPresented: .constant(true)) {
            PencilTipsSheetView()
                .padding(40)
                
        }
}
