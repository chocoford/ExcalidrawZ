//
//  ExcalidrawView.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 2022/12/27.
//

import SwiftUI
import CoreData
import UniformTypeIdentifiers

import ChocofordUI

struct ExcalidrawContainerView: View {
    @Environment(\.managedObjectContext) var viewContext
    @Environment(\.alertToast) var alertToast
    @EnvironmentObject var appPreference: AppPreference
    @EnvironmentObject var layoutState: LayoutState

    @Environment(\.colorScheme) var colorScheme
    
    @EnvironmentObject private var fileState: FileState
    
    @State private var isLoading = true
    @State private var isProgressViewPresented = true
    
    @State private var isDropping: Bool = false
    
    var fileBinding: Binding<ExcalidrawFile> {
        Binding {
            if let file = fileState.currentFile {
                do {
                    let excalidrawFile = try ExcalidrawFile(from: file.objectID, context: viewContext)
                    
                    return excalidrawFile
                } catch {
                    alertToast(error)
                    print(error)
                    return ExcalidrawFile()
                }
            } else {
                return ExcalidrawFile()
            }
        } set: { file in
            guard file.id == fileState.currentFile?.id else {
                return
            }
            fileState.updateCurrentFile(with: file)
        }
    }
    
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .center) {
                ExcalidrawView(
                    file: fileBinding,
                    isLoadingPage: $isLoading
                ) { error in
                    alertToast(error)
                    print(error)
                }
//                .ignoresSafeArea(edges: .bottom)
                .preferredColorScheme(appPreference.excalidrawAppearance.colorScheme)
                .opacity(isProgressViewPresented ? 0 : 1)
                .onChange(of: isLoading, debounce: 1) { newVal in
                    isProgressViewPresented = newVal
                    
                }
                
                if isProgressViewPresented {
                    VStack {
                        ProgressView()
                            .progressViewStyle(.circular)
                        Text(.localizable(.webViewLoadingText))
                    }
                } else if fileState.currentFile?.inTrash == true {
                    recoverOverlayView
                        .frame(width: geometry.size.width, height: geometry.size.height)
                }
                
//                if isLoadingFile {
//                    Center {
//                        VStack {
//                            Text(.localizable(.containerLoadingFileTitle))
//                            ProgressView()
//                            
//                            Text(.localizable(.containerLoadingFileDescription))
//                                .font(.footnote)
//                        }
//                    }
//                    .background(.ultraThinMaterial)
//                }
                
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
            .animation(.default, value: isProgressViewPresented)
//            .animation(.default, value: isLoadingFile)
        }
    }
    
    @MainActor @ViewBuilder
    private var recoverOverlayView: some View {
        Rectangle()
            .opacity(0)
            .contentShape(Rectangle())
            .onTapGesture {
                layoutState.isResotreAlertIsPresented.toggle()
            }
            .alert(
                .localizable(.deletedFileRecoverAlertTitle),
                isPresented: $layoutState.isResotreAlertIsPresented
            ) {
                Button(role: .cancel) {
                    layoutState.isResotreAlertIsPresented.toggle()
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
    
    private func loadMedias() {
        print("Start insert medias to IndexedDB.")
        Task {
            do {
                let context = viewContext

                let allMediasFetch = NSFetchRequest<MediaItem>(entityName: "MediaItem")
                
                let allMedias = try context.fetch(allMediasFetch)
                try await fileState.excalidrawWebCoordinator?.insertMediaFiles(
                    allMedias.compactMap{
                        .init(mediaItem: $0)
                    }
                )
            } catch {
                alertToast(error)
            }
        }
    }
}


#if DEBUG
#Preview {
    ExcalidrawContainerView()
        .frame(width: 800, height: 600)
}
#endif
