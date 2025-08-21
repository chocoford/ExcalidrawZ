//
//  TemporaryGroupRowView.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 3/5/25.
//

import SwiftUI
import CoreData

import ChocofordUI

struct TemporaryGroupRowView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.alertToast) private var alertToast
    @EnvironmentObject var fileState: FileState
    
    var body: some View {
        Button {
            fileState.currentActiveGroup = .temporary
        } label: {
            HStack {
                Label {
                    Text(.localizable(.sidebarGroupRowTitleTemporary))
                } icon: {
                    Image(systemSymbol: .clock)
                        .frame(width: 30, alignment: .leading)
                }
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(
            .excalidrawSidebarRow(
                isSelected: fileState.currentActiveGroup == .temporary,
                isMultiSelected: false
            )
        )
        .contextMenu {
            TemporaryGroupMenuItems()
                .labelStyle(.titleAndIcon)
        }
    }

}

#Preview {
    TemporaryGroupRowView()
}
