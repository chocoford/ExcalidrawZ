//
//  PencilTipsSheetView.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 2/21/25.
//

import SwiftUI

struct PencilTipsSheetView: View {
    @Environment(\.dismiss) private var dismiss
    
    @EnvironmentObject private var toolState: ToolState
    
    var body: some View {
        VStack(spacing: 16) {
            Text("Apple pencil connected")
                .font(.title)
            
            HStack(alignment: .top) {
                VStack {
                    Text("Select with finger")
                        .font(.headline)
                    
                    Image("Select with finger")
                        .resizable()
                        .scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    
                    Text(
"""
• Drag with one finger to select
• Use two fingers to move or zoom the canvas
"""
                    )
                    .font(.callout)
                    
                    Spacer()
                    if toolState.pencilInteractionMode == .fingerSelect {
                        Image(systemSymbol: .checkmark)
                            .symbolVariant(.circle)
                            .foregroundStyle(.green)
                    }
                }
                .padding()
                .background {
                    if toolState.pencilInteractionMode == .fingerSelect {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.accentColor.opacity(0.2))
                    } else if #available(iOS 17.0, *) {
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(.separator)
                    } else {
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(.secondary)
                    }
                }
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
                .onTapGesture {
                    toolState.pencilInteractionMode = .fingerSelect
                }
                                
                VStack {
                    Text("Move with finger")
                        .font(.headline)
                    
                    Image("Move with finger")
                        .resizable()
                        .scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    
                    
                    Text(
"""
• Use one finger to move the canvas
• Use two fingers to move or zoom the canvas
• Select with the dedicated tool
"""
                    )
                    .font(.callout)
                    
                    Spacer()
                    if toolState.pencilInteractionMode == .fingerMove {
                        Image(systemSymbol: .checkmark)
                            .symbolVariant(.circle)
                            .foregroundStyle(.green)
                    }
                }
                .padding()
                .background {
                    if toolState.pencilInteractionMode == .fingerMove {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.accentColor.opacity(0.2))
                    } else if #available(iOS 17.0, *) {
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(.separator)
                    } else {
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(.secondary)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    toolState.pencilInteractionMode = .fingerMove
                }
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
        .padding(40)
    }
}

#Preview {
    Color.clear
        .sheet(isPresented: .constant(true)) {
            PencilTipsSheetView()
        }
        .environmentObject(ToolState())
}
