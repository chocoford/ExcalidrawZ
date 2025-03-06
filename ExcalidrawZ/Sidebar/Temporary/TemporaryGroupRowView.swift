//
//  TemporaryGroupRowView.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 3/5/25.
//

import SwiftUI

import ChocofordUI

struct TemporaryGroupRowView: View {
    @EnvironmentObject private var fileState: FileState
    
    var body: some View {
        Button {
            fileState.isTemporaryGroupSelected = true
        } label: {
            HStack {
                Label {
                    Text("Temporary")
                } icon: {
                    Image(systemSymbol: .clock)
                }
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(ListButtonStyle(selected: fileState.isTemporaryGroupSelected))
    }
}

#Preview {
    TemporaryGroupRowView()
}
