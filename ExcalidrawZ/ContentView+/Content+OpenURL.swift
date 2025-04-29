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
    @Environment(\.openURL) private var openURL
    @Environment(\.alertToast) private var alertToast
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    
    @EnvironmentObject private var fileState: FileState
    
    @State private var externalURLToBeOpen: URL?
    @State private var isCommandKeyDown = false
    
//#if canImport(AppKit)
//    @State private var keyDownMonitor: Any?
//    @State private var keyUpMonitor: Any?
//#endif

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
#if canImport(AppKit)
                    let flags = NSEvent.modifierFlags.intersection(.deviceIndependentFlagsMask)
                    if flags.contains(.command) {
                        openURL(url)
                    } else {
                        self.externalURLToBeOpen = url
                    }
#else
                    self.externalURLToBeOpen = url
#endif
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
                if verticalSizeClass == .compact {
                    OpenURLSheetView(url: externalURLToBeOpen!)
#if os(iOS)
                        .presentationDetents([.fraction(0.3)])
                        .presentationDragIndicator(.visible)
#endif
                } else {
                    OpenURLSheetView(url: externalURLToBeOpen!)
#if os(iOS)
                        .presentationDetents([.height(240)])
                        .padding(.bottom)
#endif
                }
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
            } else if components.host == "entity" {
                onOpenDatabaseEntity(components: components)
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
    
    private func onOpenDatabaseEntity(components: URLComponents) {
        // excalidrawz://entity?objectURI=<...>
        let coordinator = PersistenceController.shared.container.persistentStoreCoordinator
        guard let objectURIEncoded = components.queryItems?.first(where: {$0.name == "objectURI"})?.value,
              let decoded = objectURIEncoded.removingPercentEncoding,
              let url = URL(string: decoded),
              url.scheme == "x-coredata",
              let objectID = coordinator.managedObjectID(forURIRepresentation: url) else {
            return
        }
        
        let context = viewContext
        
        Task {
            await context.perform {
                let object = context.object(with: objectID)
                
                if let file = object as? File {
                    if let group = file.group {
                        fileState.expandToGroup(group.objectID)
                        fileState.currentGroup = group
                    }
                    fileState.currentFile = file
                } else if let group = object as? Group {
                    fileState.expandToGroup(group.objectID)
                    fileState.currentGroup = group
                } else if let folder = object as? LocalFolder {
                    fileState.expandToGroup(folder.objectID)
                    fileState.currentLocalFolder = folder
                }
            }
        }
    }
}


struct OpenURLSheetView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    var url: URL
    
    enum URLType {
        case web
        case mail
        case file
        case app
    }
    var urlType: URLType {
        if url.scheme?.hasPrefix("http") == true {
            .web
        } else if url.scheme == "mailto" {
            .mail
        } else if url.isFileURL {
            .file
        } else {
            .app
        }
    }
    
    
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
        VStack(spacing: 10) {
            VStack(spacing: 6) {
                switch urlType {
                    case .web:
                        Text(.localizable(.externalLinkOpenSheetWebLinkTitle))
                            .font(.title)
                        Text(.localizable(.externalLinkOpenSheetWebLinkDescription))
                    case .mail:
                        Text(.localizable(.externalLinkOpenSheetMailLinkTitle))
                            .font(.title)
                        Text(.localizable(.externalLinkOpenSheetMailLinkDescription))
                    case .file:
                        Text(.localizable(.externalLinkOpenSheetLocalURLTitle))
                            .font(.title)
                        Text(.localizable(.externalLinkOpenSheetLocalURLDescription))
                    case .app:
                        Text(.localizable(.externalLinkOpenSheetExternalAppLinkTitle))
                            .font(.title)
                        Text(.localizable(.externalLinkOpenSheetExternalAppLinkDescription))
                }
            }
            
            Spacer(minLength: 0)
            
            VStack(spacing: 4) {
                switch urlType {
                    case .web:
                        Image(systemSymbol: .globe)
                    case .mail:
                        Image(systemSymbol: .envelope)
                    case .file:
#if os(macOS)
                        Image(platformImage: NSWorkspace.shared.icon(forFile: url.filePath))
#elseif os(iOS)
                    Image(platformImage: UIImage.icon(forFileURL: url))
#endif
                    case .app:
                        EmptyView()
                }
                
                switch urlType {
                    case .mail:
                        Text(
                            URLComponents(url: url, resolvingAgainstBaseURL: false)?.path ?? String(localizable: .generalUnknown)
                        )
                    case .file:
                        Text(url.lastPathComponent)
                    default:
                        Text(url.absoluteString)
                            .fontWeight(.semibold)
                }

            }
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
            
            Spacer(minLength: 0)
            
            VStack {
                Button {
                    openURL(url)
                } label: {
                    SwiftUI.Group {
                        switch urlType {
                            case .web:
                                Text(.localizable(.externalLinkOpenSheetButtonOpenWebLink))
                            case .mail:
                                Text(.localizable(.externalLinkOpenSheetButtonOpenMailLink))
                            case .file:
                                Text(.localizable(.externalLinkOpenSheetButtonOpenLocalURL))
                            case .app:
                                Text(.localizable(.externalLinkOpenSheetButtonOpenExternalApp))
                        }
                    }
#if os(macOS)
                    .frame(width: 160)
#else
                    .frame(maxWidth: .infinity)
#endif
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.return)
#if os(macOS)
                Button {
                    dismiss()
                } label: {
                    Text(.localizable(.generalButtonCancel))
                        .frame(width: 160)
                }
                .keyboardShortcut(.escape)
#endif
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
        .overlay(alignment: .bottomTrailing) {
            Text("Don't want to see this pop-up?")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(6)
                .popoverHelp("You can directly open the link by holding down the ⌘ key.")
        }
#else
        .padding(.top, 20)
        .padding(.horizontal, 20)
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
        let newWidth: CGFloat = isPreviewWebView ? 900 : 400
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
