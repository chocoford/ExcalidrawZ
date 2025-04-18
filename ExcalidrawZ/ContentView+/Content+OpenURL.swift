//
//  Content+OpenURL.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 3/18/25.
//

import SwiftUI
import CoreData
import WebKit

import ChocofordUI

struct OpenURLModifier: ViewModifier {
    @Environment(\.managedObjectContext) var viewContext
    @Environment(\.alertToast) private var alertToast
    
    @EnvironmentObject private var fileState: FileState
    
    @State private var externalURLToBeOpen: URL?
    
    func body(content: Content) -> some View {
        content
            .onOpenURL { url in
                onOpenURL(url)
            }
            .onReceive(NotificationCenter.default.publisher(for: .shouldOpenExternalURL)) { notification in
                guard let url = notification.object as? URL else { return }
                
                if url.scheme == "excalidrawz" || url.isFileURL && url.pathExtension == "excalidraw" {
                    self.onOpenURL(url)
                } else {
                    self.externalURLToBeOpen = url
                }
            }
            .sheet(
                isPresented: Binding(
                    get: {
                        externalURLToBeOpen != nil
                    },
                    set: { val in
                        if !val {
                            externalURLToBeOpen = nil
                        }
                    }
                )
            ) {
                OpenURLSheetView(url: externalURLToBeOpen!)
#if os(iOS)
                    .presentationDetents([.fraction(0.35)])
#endif
            }
    }
    
    // MARK: - Handle OpenURL
    private func onOpenURL(_ url: URL) {
        if url.isFileURL {
            onOpenLocalFile(url)
        } else if url.scheme == "excalidrawz" {
            guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
                return
            }
            if components.host == "collab" {
                onOpenCollabURL(url, components: components)
            } else {
                self.externalURLToBeOpen = url
            }
        }
    }
    
    private func onOpenLocalFile(_ url: URL) {
        // check if it is already in LocalFolder
        let context = viewContext
        var canAddToTemp = true
        do {
            try context.performAndWait {
                let folderFetchRequest = NSFetchRequest<LocalFolder>(entityName: "LocalFolder")
                folderFetchRequest.predicate = NSPredicate(format: "filePath == %@", url.deletingLastPathComponent().filePath)
                guard let folder = try context.fetch(folderFetchRequest).first else {
                    return
                }
                canAddToTemp = false
                Task {
                    await MainActor.run {
                        fileState.currentLocalFolder = folder
                        fileState.expandToGroup(folder.objectID)
                    }
                    try? await Task.sleep(nanoseconds: UInt64(1e+9 * 0.1))
                    await MainActor.run {
                        fileState.currentLocalFile = url
                    }
                }
            }
        } catch {
            alertToast(error)
        }
        
        guard canAddToTemp else { return }
        
        // logger.debug("on open url: \(url, privacy: .public)")
        if !fileState.temporaryFiles.contains(where: {$0 == url}) {
            fileState.temporaryFiles.append(url)
        }
        if !fileState.isTemporaryGroupSelected || fileState.currentTemporaryFile == nil {
            fileState.isTemporaryGroupSelected = true
            fileState.currentTemporaryFile = fileState.temporaryFiles.first
        }
        // save a checkpoint immediately.
        Task.detached {
            do {
                try await context.perform {
                    let newCheckpoint = LocalFileCheckpoint(context: context)
                    newCheckpoint.url = url
                    newCheckpoint.updatedAt = .now
                    newCheckpoint.content = try Data(contentsOf: url)
                    
                    context.insert(newCheckpoint)
                    try context.save()
                }
            } catch {
                await alertToast(error)
            }
        }
    }
    
    private func onOpenCollabURL(_ url: URL, components: URLComponents) {
        let encodedRoomID = String(components.path.dropFirst())
        if let roomID = CollabRoomIDCoder.shared.decode(encodedString: encodedRoomID),
           let nameItem = components.queryItems?.first(where: {$0.name == "name"}) {
            let context = PersistenceController.shared.container.newBackgroundContext()
            Task.detached {
                do {
                    // fetch the room
                    try await context.perform {
                        let roomFetchRequest = NSFetchRequest<CollaborationFile>(entityName: "CollaborationFile")
                        roomFetchRequest.predicate = NSPredicate(format: "roomID = %@", roomID)
                        let room: CollaborationFile
                        if let firstRoom = try context.fetch(roomFetchRequest).first {
                            room = firstRoom
                        } else {
                            let newRoom = CollaborationFile(
                                name: nameItem.value ?? String(localizable: .generalUntitled),
                                content: ExcalidrawFile().content,
                                isOwner: false,
                                context: context
                            )
                            newRoom.roomID = roomID
                            context.insert(newRoom)
                            try context.save()
                            room = newRoom
                        }
                        let roomID = room.objectID
                        Task {
                            await MainActor.run {
                                fileState.isInCollaborationSpace = true
                                if case let room as CollaborationFile = viewContext.object(with: roomID) {
                                    fileState.currentCollaborationFile = .room(room)
                                }
                            }
                        }
                    }
                } catch {
                    await alertToast(error)
                }
            }
        }
    }
}


struct OpenURLSheetView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    var url: URL
    
    @State private var isPreviewWebView: Bool = false
    @State private var isPreviewWebViewLoading: Bool = false
#if canImport(AppKit)
    typealias PlatformWindow = NSWindow
#elseif canImport(UIKit)
    typealias PlatformWindow = UIWindow
#endif
    
    @State private var window: PlatformWindow?
    
    @State private var viewWidth: CGFloat = 400
    @State private var viewHeight: CGFloat = 240
    
    var body: some View {
        VStack {
            Text(.localizable(.externalLinkOpenSheetTitle))
                .font(.title)
            
            Text(.localizable(.externalLinkOpenSheetDescription))
            Text(url.absoluteString)
                .fontWeight(.semibold)
            
            
#if os(macOS)
            if isPreviewWebView {
                ZStack {
                    PreviewWebView(url: url, isLoading: $isPreviewWebViewLoading)
                    
                    if isPreviewWebViewLoading {
                        Rectangle()
                            .fill(.regularMaterial)
                            .overlay {
                                ProgressView()
                            }
                    }
                }
                .animation(.default, value: isPreviewWebViewLoading)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay {
                    if #available(macOS 13.0, iOS 17.0, *) {
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(.separator)
                    } else {
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(.secondary)
                    }
                }
                .background {
                    RoundedRectangle(cornerRadius: 12)
                        .shadow(radius: 2)
                }
            }
#endif
            
            VStack {
                Button {
                    openURL(url)
                } label: {
                    Text(.localizable(.externalLinkOpenSheetButtonContinue))
                        .frame(width: 160)
                }
                .buttonStyle(.borderedProminent)
                
                Button {
                    dismiss()
                } label: {
                    Text(.localizable(.generalButtonCancel))
                        .frame(width: 160)
                }
            }
            .controlSize({
                if #available(macOS 14.0, iOS 17.0, *) {
                    .extraLarge
                } else {
                    .large
                }
            }())
        }
#if os(macOS)
        .padding(40)
        .frame(width: viewWidth, height: viewHeight)
        .overlay(alignment: .topTrailing) {
            if url.scheme?.starts(with: "http") == true {
                Button {
                    isPreviewWebView.toggle()
                } label: {
                    Label("Preview", systemSymbol: .eye)
                        .symbolVariant(isPreviewWebView ? .none : .slash)
                        .labelStyle(.iconOnly)
                        .animation(nil, value: isPreviewWebView)
                }
                .buttonStyle(.text)
                .padding(40)
            }
        }
#endif
        .animation(.smooth, value: isPreviewWebView)
        .bindWindow($window)
#if os(macOS)
        .onChange(of: isPreviewWebView) { newValue in
            changeViewSize(isPreviewWebView: newValue, window: window)
        }
        .watchImmediately(of: window) { newValue in
            changeViewSize(isPreviewWebView: isPreviewWebView, window: newValue)
        }
#endif
    }
#if os(macOS)
    private func changeViewSize(isPreviewWebView: Bool, window: PlatformWindow?) {
        guard let window else { return }
        let newWidth: CGFloat = isPreviewWebView ? 900 : 360
        let newHeight: CGFloat = isPreviewWebView ? 600 : 240
        window.setFrame(
            NSRect(
                origin: window.frame.origin,
                size: CGSize.init(
                    width: newWidth, height: newHeight
                )
            ),
            display: true,
            animate: true
        )
        withAnimation(.smooth) {
            viewWidth = newWidth
            viewHeight = newHeight
        }
    }
#endif
}


#if os(macOS)
struct PreviewWebView: NSViewRepresentable {
    var url: URL
    
    @Binding var isLoading: Bool
    
    func makeNSView(context: Context) -> WKWebView {
        let webView = WKWebView()
        
        webView.load(URLRequest(url: url))
        DispatchQueue.main.async {
            self.isLoading = true
        }
        
        webView.navigationDelegate = context.coordinator
        
        return webView
    }
    
    func updateNSView(_ nsView: WKWebView, context: Context) {
        
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }
    
    class Coordinator: NSObject, WKNavigationDelegate {
        var parent: PreviewWebView
        
        init(parent: PreviewWebView) {
            self.parent = parent
        }
        
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            DispatchQueue.main.async {
                self.parent.isLoading = false
            }
        }
    }
}

#endif
