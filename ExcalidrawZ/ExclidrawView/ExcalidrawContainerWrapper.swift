//
//  ExcalidrawContainerWrapper.swift
//  ExcalidrawZ
//
//  Created by Chocoford on 9/23/25.
//

import SwiftUI

struct ExcalidrawContainerWrapper: View {
    @Environment(\.managedObjectContext) var viewContext
    @Environment(\.alertToast) var alertToast

    @EnvironmentObject var fileState: FileState

    @Binding var activeFile: FileState.ActiveFile?
    var interactionEnabled: Bool
    
    init(
        activeFile: Binding<FileState.ActiveFile?>,
        interactionEnabled: Bool = true
    ) {
        self._activeFile = activeFile
        self.interactionEnabled = interactionEnabled
    }
    
    var localFileBinding: Binding<ExcalidrawFile?> {
        Binding<ExcalidrawFile?> {
            switch activeFile {
                case .file(let file):
                    return try? ExcalidrawFile(from: file.objectID, context: viewContext)
                case .localFile(let url):
                    return try? ExcalidrawFile(contentsOf: url)
                case .temporaryFile(let url):
                    return try? ExcalidrawFile(contentsOf: url)
                default:
                    return nil
            }
        } set: { val in
            guard let val else { return }
            do {
                switch activeFile {
                    case .file(let file):
                        if file.id == val.id {
                            // Everytime load a new file will cause an actual update.
                            let oldElements = try ExcalidrawFile(
                                from: file.objectID,
                                context: viewContext
                            ).elements
                            if val.elements == oldElements {
                                print("[updateCurrentFile] no updates, ignored.")
                                return
                            }
                            fileState.updateFile(file, with: val)
                        }
                    case .localFile(let url):
                        guard case .localFolder(let folder) = fileState.currentActiveGroup else { return }
                        Task {
                            try folder.withSecurityScopedURL { _ in
                                do {
                                    let oldElements = try ExcalidrawFile(contentsOf: url).elements
                                    if val.elements == oldElements {
                                        print("[updateCurrentFile] no updates, ignored.")
                                        return
                                    }
                                    try await fileState.updateLocalFile(
                                        to: url,
                                        with: val,
                                        context: viewContext
                                    )
                                } catch {
                                    alertToast(error)
                                }
                            }
                        }
                    case .temporaryFile(let url):
                        Task {
                            do {
                                let oldElements = try ExcalidrawFile(contentsOf: url).elements
                                if val.elements == oldElements {
                                    print("[updateCurrentFile] no updates, ignored.")
                                    return
                                }
                                try await fileState.updateLocalFile(
                                    to: url,
                                    with: val,
                                    context: viewContext
                                )
                            } catch {
                                alertToast(error)
                            }
                        }
                    default:
                        break
                }
            } catch { }
        }
    }
    
    var isInCollaborationSpace: Bool {
        if case .collaborationFile = activeFile {
            return true
        } else {
            return false
        }
    }
    
    var body: some View {
        ZStack {
            ExcalidrawContainerView(
                file: localFileBinding,
                interactionEnabled: interactionEnabled
            )
            .opacity(isInCollaborationSpace ? 0 : 1)
            .allowsHitTesting(!isInCollaborationSpace)

            ExcalidrawCollabContainerView()
                .opacity(isInCollaborationSpace ? 1 : 0)
                .allowsHitTesting(isInCollaborationSpace)
        }
#if os(iOS)
        .modifier(ApplePencilToolbarModifier())
        .sheet(isPresented: $isSettingsPresented) {
            if #available(macOS 13.0, iOS 16.4, *) {
                SettingsView()
                    .presentationContentInteraction(.scrolls)
            } else {
                SettingsView()
            }
        }
#endif
//        .environmentObject(toolState)
//        .overlay {
//            splitViewsContent()
//        }
        .allowsHitTesting(interactionEnabled)
    }
}
