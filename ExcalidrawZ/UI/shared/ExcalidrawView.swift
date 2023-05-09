//
//  ExcalidrawView.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 2022/12/27.
//

import SwiftUI
import ChocofordUI

struct ExcalidrawView: View {
    @EnvironmentObject var store: AppStore

    @State private var isLoading = true
    @State private var showRestoreAlert = false

    private var currentFile: Binding<File?> {
        store.binding(for: \.currentFile,
                      toAction: {
            return .setCurrentFile($0)
        })
    }
    
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .center) {
                WebView(store: store,
                        currentFile: currentFile,
                        loading: $isLoading)
                .opacity(isLoading ? 0 : 1)
                if isLoading {
                    VStack {
                        CircularProgressView()
                        Text("Loading...")
                    }
                } else if currentFile.wrappedValue?.inTrash == true {
                    recoverOverlayView
                        .frame(width: geometry.size.width, height: geometry.size.height)
                }
            }
            .transition(.opacity)
            .animation(.default, value: isLoading)
            .onChange(of: isLoading) { newValue in
                if !newValue {
                    store.send(.setCurrentFileToFirst)
                }
            }
        }
    }
}

extension ExcalidrawView {
    @ViewBuilder private var recoverOverlayView: some View {
        Rectangle()
            .opacity(0)
            .contentShape(Rectangle())
            .onTapGesture {
                showRestoreAlert.toggle()
            }
            .onLongPressGesture(perform: {
                showRestoreAlert.toggle()
            })
            .alert("Recently deleted files can’t be edited.", isPresented: $showRestoreAlert) {
                Button(role: .cancel) {
                    showRestoreAlert.toggle()
                } label: {
                    Text("Cancel")
                }

                Button {
                    if let file = currentFile.wrappedValue {
                        store.send(.recoverFile(file))
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
        ExcalidrawView()
            .environmentObject(AppStore.preview)
            .frame(width: 800, height: 600)
//        if #available(macOS 13.0, *) {
//            NavigationSplitView {
//                
//            } detail: {
//                Center {
//                }
//                .overlay {
//                    CircularProgressView()
//                }
//            }
//        } else {
//            // Fallback on earlier versions
//            Text("")
//        }

    }
}
#endif
