//
//  WebView.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 2022/12/25.
//

import Foundation
import SwiftUI
import WebKit
import Combine
import OSLog
import ComposableArchitecture

struct ExcalidrawStore: ReducerProtocol {
    struct State: Equatable {
        var currentFile: File?
        
        var didUpdateFile: Bool = false
        var isCreatingFile: Bool = false
        var ignoreUpdate: Bool = false
        var ignoreUpdateID: UUID = UUID()
        
        var coordinator: ExcalidrawWebView.Coordinator?
    }
    
    enum Action: Equatable {
        case setCurrentFile(File?)
        case updateCoordinator(ExcalidrawWebView.Coordinator)
        
        case loadFile(File)
        case loadCurrentFile
        case restoreCheckpoint(Data)
        
        case updateCurrentFile(Data)
        
        /// fix the bug:
        /// load file during saving will overwrite the loaded file
        /// with previous file data.
        /// -----------------
        /// Just stopping update when changing current file for a while.
        /// In this case we set it 1.5 seconds (The saving interval
        /// is 2 seconds)
        case freezeUpdate
        case watchUpdate(UUID)
        
        case applyColorSceme(ColorScheme)
        
        case exportPNGImage
        
        case setError(_ error: AppError)
        
        case delegate(Delegate)
        
        enum Delegate: Equatable {
            case onFinishLoading
            case onBeginExport(ExportImageStore.State)
            case onExportDone
            
            case didUpdateFile(File)
            case needCreateFile(Data)
        }
    }
    
    @Dependency(\.errorBus) var errorBus
    @Dependency(\.coreData) var coreData
    
    var body: some ReducerProtocol<State, Action> {
        Reduce { state, action in
            switch action {
                case .setCurrentFile(let file):
                    state.didUpdateFile = false
                    // prevent update when setting file.
                    state.ignoreUpdate = true
                    state.currentFile = file
                    state.isCreatingFile = false
                    return .send(.loadCurrentFile)
                    
                case .delegate:
                    return .none
                    
                case .loadFile(let file):
                    return .run { [state] send in
                        do {
                            await send(.freezeUpdate)
                            try await state.coordinator?.loadFile(from: file)
                        } catch {
                            await send(.setError(.init(error))) 
                        }
                    }
                case .loadCurrentFile:
                    if let file = state.currentFile {
                        return .send(.loadFile(file))
                    } else {
                        return .none
                    }
                    
                case .restoreCheckpoint(let data):
                    guard let fileWithNewData = state.currentFile else { return .none }
                    state.didUpdateFile = false
                    fileWithNewData.content = data
                    return .send(.loadFile(fileWithNewData))
                    
                case .updateCurrentFile(let fileData):
                    guard !state.ignoreUpdate || state.currentFile?.inTrash != true else { return .none }
                    do {
                        if let file = state.currentFile {
                            try file.updateElements(with: fileData, newCheckpoint: !state.didUpdateFile)
                            coreData.provider.save()
                            state.didUpdateFile = true
                            return .send(.delegate(.didUpdateFile(file)))
                        } else if !state.isCreatingFile {
                            state.isCreatingFile = true
                            return .send(.delegate(.needCreateFile(fileData)))
                        }
                        return .none
                    } catch {
                        return .send(.setError(.init(error)))
                    }
                    
                case .freezeUpdate:
                    let id = UUID()
                    state.ignoreUpdateID = id
                    state.ignoreUpdate = true
                    return .run { send in
                        try await Task.sleep(nanoseconds: 1500 * 10^6)
                        await send(.watchUpdate(id))
                    }
                    
                case .watchUpdate(let id):
                    guard id == state.ignoreUpdateID else { return .none }
                    state.ignoreUpdate = false
                    return .none
                    
                case .applyColorSceme(let colorScheme):
                    guard let coordinator = state.coordinator else { return .none }
                    return .run { send in
                        do {
                            try await coordinator.changeColorMode(dark: colorScheme == .dark)
                        } catch {
                            await send(.setError(.init(error)))
                        }
                    }
                    
                case .exportPNGImage:
                    return .run { [state] send in
                        do {
                            try await state.coordinator?.exportPNG()
                        } catch {
                            await send(.setError(.init(error)))
                        }
                    }
                    
                case .updateCoordinator(let coordinator):
                    state.coordinator = coordinator
                    return .none
                    
                case .setError(let error):
                    errorBus.submit(error)
                    return .none
            }
        }
    }
}

struct ExcalidrawWebView {
    @Environment(\.colorScheme) var colorScheme

    let store: StoreOf<ExcalidrawStore>
    let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "WebView")
    
    @State private var oldAppearance: AppSettingsStore.Appearance?
}

#if os(macOS)
extension ExcalidrawWebView: NSViewRepresentable {
    typealias NSViewType = WKWebView

    func makeNSView(context: Context) -> WKWebView {
        return context.coordinator.webView
    }
    
    func updateNSView(_ nsView: WKWebView, context: Context) {
        let webView = context.coordinator.webView
        context.coordinator.parent = self
        guard !webView.isLoading else {
            return
        }
    }

    func makeCoordinator() -> Coordinator {
        let coordinator = Coordinator(self)
        self.store.send(.updateCoordinator(coordinator))
        return coordinator
    }
}

#elseif os(iOS)

#endif
