//
//  ExcalidrawView.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 2022/12/27.
//

import SwiftUI
import ChocofordUI
import UniformTypeIdentifiers

struct ExcalidrawContainerView: View {
    @Environment(\.alertToast) var alertToast
    @EnvironmentObject var appPreference: AppPreference

    @Environment(\.colorScheme) var colorScheme
    
    @EnvironmentObject private var fileState: FileState
    
    @State private var isLoading = true
    @State private var isLoadingFile = false
    @State private var resotreAlertIsPresented = false
    
    @State private var isDropping: Bool = false
    
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .center) {
                ExcalidrawView(isLoadingPage: $isLoading, isLoadingFile: $isLoadingFile) {
                    alertToast($0)
                    print($0)
                }
                .preferredColorScheme(appPreference.excalidrawAppearance.colorScheme)
                .opacity(isLoading ? 0 : 1)
                
                if isLoading {
                    VStack {
                        ProgressView()
                            .progressViewStyle(.circular)
                        Text(.localizable(.webViewLoadingText))
                    }
                } else if fileState.currentFile?.inTrash == true {
                    recoverOverlayView
                        .frame(width: geometry.size.width, height: geometry.size.height)
                }
                
                if isLoadingFile {
                    Center {
                        VStack {
                            Text(.localizable(.containerLoadingFileTitle))
                            ProgressView()
                            
                            Text(.localizable(.containerLoadingFileDescription))
                                .font(.footnote)
                        }
                    }
                    .background(.ultraThinMaterial)
                }
                
                // This will work
                ///* but it will conflict with image drop
//                Color.clear
//                    .onDrop(of: [.excalidrawFile]) { providers, location in
//                        let alertToast = alertToast
//                        let fileState = fileState
//                        for provider in providers {
//                            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier) { item, error in
//                                guard let urlData = item as? Data else { return }
//                                let url = URL(dataRepresentation: urlData, relativeTo: nil)
//                                if let error {
//                                    alertToast(error)
//                                    return
//                                }
//                                if let url {
//                                    do {
//                                        try fileState.importFile(url)
//                                    } catch {
//                                        alertToast(error)
//                                    }
//                                }
//                            }
//                        }
//                        return true
//                    } dropMask: {
//                        Center {
//                            VStack {
//                                Image(systemSymbol: .docFillBadgePlus)
//                                    .symbolRenderingMode(.multicolor)
//                                    .resizable()
//                                    .scaledToFit()
//                                    .frame(height: 100)
//                                Text("Import a excalidraw file")
//                                    .font(.largeTitle)
//                                Text("ExcalidrawZ will create a new file for you to store the imported file.")
//                                    .font(.footnote)
//                            }
//                        }
//                        .background(.ultraThinMaterial)
//                    }
                 
            }
            .transition(.opacity)
            .animation(.default, value: isLoading)
            .animation(.default, value: isLoadingFile)
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
            .alert(.localizable(.deletedFileRecoverAlertTitle), isPresented: $resotreAlertIsPresented) {
                Button(role: .cancel) {
                    resotreAlertIsPresented.toggle()
                } label: {
                    Text(.localizable(.deletedFileRecoverAlertButtonCancel))
                }
                
                Button {
                    // Recover file
                    if let currentFile = fileState.currentFile {
                        fileState.recoverFile(currentFile)
                    }
                } label: {
                    Text(.localizable(.deletedFileRecoverAlertButtonRecover))
                }
                
            } message: {
                Text(.localizable(.deletedFileRecoverAlertMessage))
            }
    }
}


extension UTType {
    static var excalidrawFile: UTType {
        UTType(importedAs: "com.chocoford.excalidrawFile")
    }
    static var excalidrawlibFile: UTType {
        UTType(importedAs: "com.chocoford.excalidrawlibFile")
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
