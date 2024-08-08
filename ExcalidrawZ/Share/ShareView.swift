//
//  ShareView.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 2023/8/7.
//

import SwiftUI

import ChocofordUI
import SwiftyAlert

struct ShareView: View {
    @Environment(\.dismiss) var dismiss
    @Environment(\.alertToast) var alertToast
    
    var sharedFile: File
    
    enum Route: Hashable {
        case exportImage
        case exportFile
    }
    
    @State private var route: NavigationPath = .init()
    
    
    var body: some View {
        NavigationStack(path: $route) {
            List {
                squareButton {
                    route.append(Route.exportImage)
                } label: {
                    Label("Export image", systemImage: "photo")
                        .font(.title3)
                }
                squareButton {
                    route.append(Route.exportFile)
                } label: {
                    Label("Export current file", systemImage: "doc")
                        .font(.title3)
                }
                squareButton {
                    do {
                        try archiveAllFiles()
                    } catch {
                        alertToast(error)
                    }
                } label: {
                    Label("Archive files", systemImage: "archivebox")
                        .font(.title3)
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Text("Dismiss")
                    }
                }
            }
//            .opacity(viewStore.path.count > 0 ? 0 : 1)
            .navigationTitle("Share")
        }
        .navigationDestination(for: Route.self) { route in
            switch route {
                case .exportImage:
                    ExportImageView()
                case .exportFile:
                    ExportFileView(file: sharedFile)
            }
        }
        .frame(width: 400, height: 300)
    }
    
    @MainActor @ViewBuilder
    private func squareButton<Label: View>(
        action: @escaping () -> Void,
        @ViewBuilder label: () -> Label
    ) -> some View {
        Button {
            action()
        } label: {
            HStack {
                label()
                Spacer()
            }
            .frame(width: nil, height: 50)
        }
        .buttonStyle(ListButtonStyle())
    }
}

#if DEBUG
//#Preview {
//    if #available(macOS 13.0, *) {
//        return ShareView(
//            store: .init(initialState: .init(currentFile: .preview)) {
//                ShareStore()
//            })
//    } else {
//        // Fallback on earlier versions
//        return EmptyView()
//    }
//}
#endif
