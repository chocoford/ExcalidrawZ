//
//  ContentViewLagacy.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 4/1/25.
//

import SwiftUI

struct ContentViewLagacy: View {
    @Environment(\.alertToast) var alertToast
    @EnvironmentObject var fileState: FileState
    @EnvironmentObject var layoutState: LayoutState
    
    var body: some View {
        ZStack {
            ContentViewDetail(isSettingsPresented: .constant(false))
                .layoutPriority(1)
            
            HStack {
                if layoutState.isSidebarPresented {
                    SidebarView()
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .background {
                            RoundedRectangle(cornerRadius: 12)
                                .fill(.regularMaterial)
                                .shadow(radius: 4)
                        }
                        .transition(.move(edge: .leading))
                }
                Spacer()
            }
            .animation(.easeOut, value: layoutState.isSidebarPresented)
            .animation(.easeOut, value: layoutState.isInspectorPresented)
            .padding(.top, 10)
            .padding(.horizontal, 10)
            .padding(.bottom, 40)
        }
    }
}
