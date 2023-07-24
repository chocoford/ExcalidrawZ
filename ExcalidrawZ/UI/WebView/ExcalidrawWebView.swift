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
        var coordinator: ExcalidrawWebView.Coordinator?
    }
    
    enum Action: Equatable {
        case setCurrentFile(File)
        case updateCoordinator(ExcalidrawWebView.Coordinator)
        
        case loadFile(File)
        case exportPNGImage
        
        case delegate(Delegate)
        
        enum Delegate: Equatable {
            case onFinishLoading
            case onBeginExport(ExportStore.State)
            case onExportDone
        }
    }
    
    var body: some ReducerProtocol<State, Action> {
        Reduce { state, action in
            switch action {
                case .setCurrentFile(let file):
                    state.currentFile = file
                    return .none
                    
                case .delegate:
                    return .none
                    
                case .loadFile(let file):
                    return .run { [state] send in
                        do {
                            try await state.coordinator?.loadFile(from: file)
                        } catch {
                            
                        }
                    }
                    
                case .exportPNGImage:
                    return .run { [state] send in
                        do {
                            try await state.coordinator?.exportPNG()
                        } catch {
                            
                        }
                    }
                    
                default:
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
        self.store.send(.updateCoordinator(context.coordinator))
        guard !webView.isLoading else {
            return
        }

    }

    func makeCoordinator() -> Coordinator {
        return Coordinator(self)
    }
}

#elseif os(iOS)

#endif
