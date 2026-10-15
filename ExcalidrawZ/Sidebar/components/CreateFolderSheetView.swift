//
//  CreateFolderSheetView.swift
//  ExcalidrawZ
//
//  Created by Chocoford on 9/25/25.
//

import SwiftUI
import SwiftyAlert
import CoreData

import ChocofordUI

struct CreateFolderModifier: ViewModifier {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.containerHorizontalSizeClass) private var containerHorizontalSizeClass
    @Environment(\.alertToast) private var alertToast
    @EnvironmentObject var fileState: FileState
    @EnvironmentObject private var localFolderState: LocalFolderState
    

    @Binding var isPresented: Bool
    var parentFolderID: NSManagedObjectID?
    @State private var parentFolder: LocalFolder?
    
    init(isPresented: Binding<Bool>, parentFolderID: NSManagedObjectID?) {
        self._isPresented = isPresented
        self.parentFolderID = parentFolderID
    }
    
    @State private var initialNewGroupName = ""
    
    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $isPresented) {
                if containerHorizontalSizeClass == .compact {
                    createFolderSheetView()
#if os(iOS)
                        .presentationDetents([.height(140)])
                        .presentationDragIndicator(.visible)
#endif
                } else if #available(iOS 18.0, macOS 13.0, *) {
                    createFolderSheetView()
                        .scrollDisabled(true)
                        .frame(width: 400, height: 140)
#if os(iOS)
                        .presentationSizing(.fitted)
#endif
                } else {
                    createFolderSheetView()
                }
            }
            .task(id: parentFolderID) {
                guard let parentFolderID else { return }
                parentFolder = viewContext.object(with: parentFolderID) as? LocalFolder
            }
    }
    
    @ViewBuilder
    private func createFolderSheetView() -> some View {
        CreateGroupSheetView(
            name: $initialNewGroupName,
            createType: .localFolder
        ) { name in
            do {
                let context = viewContext
                guard let parentFolder,
                      let url = parentFolder.url else {
                    struct URLNotFoundError: Error {}
                    throw URLNotFoundError()
                }
                let newURL = url.appendingPathComponent(name, conformingTo: .directory)
                guard !FileManager.default.fileExists(at: newURL) else {
                    struct FolderAlreadyExistsError: LocalizedError {
                        var errorDescription: String? {
                            "Folder already exists"
                        }
                    }
                    throw FolderAlreadyExistsError()
                }

                try parentFolder.withSecurityScopedURL { scopedURL in
                    try FileManager.default.createDirectory(
                        at: scopedURL.appendingPathComponent(name, conformingTo: .directory),
                        withIntermediateDirectories: false
                    )
                }
                
                try parentFolder.refreshChildren(context: context)
                localFolderState.objectWillChange.send()
                localFolderState.refreshFilesPublisher.send()
            } catch {
                alertToast(error)
            }
        }
        .controlSize(.large)
    }
}
