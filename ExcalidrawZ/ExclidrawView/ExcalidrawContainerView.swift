//
//  ExcalidrawView.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 2022/12/27.
//

import SwiftUI
import ChocofordUI

struct ExcalidrawContainerView: View {
    @Environment(\.alertToast) var alertToast
    @EnvironmentObject var appPreference: AppPreference

    @Environment(\.colorScheme) var colorScheme
    
    @EnvironmentObject private var fileState: FileState
    
    @State private var isLoading = true
    @State private var resotreAlertIsPresented = false
    
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .center) {
                ExcalidrawWebView(isLoading: $isLoading) {
                    alertToast($0)
                }
                .preferredColorScheme(appPreference.excalidrawAppearance.colorScheme)
                .opacity(isLoading ? 0 : 1)
                
                if isLoading {
                    VStack {
                        ProgressView()
                            .progressViewStyle(.circular)
                        Text("Loading...")
                    }
                } else if fileState.currentFile?.inTrash == true {
                    recoverOverlayView
                        .frame(width: geometry.size.width, height: geometry.size.height)
                }
            }
            .transition(.opacity)
            .animation(.default, value: isLoading)
        }
    }
    
    @MainActor @ViewBuilder
    private var recoverOverlayView: some View {
        Rectangle()
            .opacity(0)
            .contentShape(Rectangle())
            .onTapGesture {
                resotreAlertIsPresented.toggle()
            }
            .alert("Recently deleted files can’t be edited.", isPresented: $resotreAlertIsPresented) {
                Button(role: .cancel) {
                    resotreAlertIsPresented.toggle()
                } label: {
                    Text("Cancel")
                }
                
                Button {
                    // Recover file
                    if let currentFile = fileState.currentFile {
                        fileState.recoverFile(currentFile)
                    }
                } label: {
                    Text("Recover")
                }
                
            } message: {
                Text("To edit this file, you’ll need to recover it.")
            }
    }
}


#if DEBUG
struct ExcalidrawView_Previews: PreviewProvider {
    static var previews: some View {
        ExcalidrawContainerView()
            .frame(width: 800, height: 600)
    }
}
#endif
