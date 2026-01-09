//
//  CreateFolderSheetView.swift
//  ExcalidrawZ
//
//  Created by Chocoford on 9/25/25.
//

import SwiftUI
import CoreData

import ChocofordUI

struct CreateFolderModifier: ViewModifier {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.containerHorizontalSizeClass) private var containerHorizontalSizeClass
    @Environment(\.alertToast) private var alertToast
    @EnvironmentObject var fileState: FileState
    

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
            .watch(value: parentFolderID) { newValue in
                guard let newValue else { return }
                self.parentFolder = viewContext.object(with: newValue) as? LocalFolder
            }
    }
    
    @MainActor @ViewBuilder
    private func createFolderSheetView() -> some View {
        CreateGroupSheetView(
            name: $initialNewGroupName,
            createType: .localFolder
        ) { name in
            do {
                let context = viewContext
                guard let url = parentFolder?.url else {
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
                
                try FileManager.default.createDirectory(
                    at: newURL,
                    withIntermediateDirectories: false
                )
                
                let newFolder = try LocalFolder(url: newURL, context: context)
                newFolder.parent = parentFolder
            } catch {
                alertToast(error)
            }
        }
        .controlSize(.large)
    }
}
