//
//  ShareView.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 2023/8/7.
//

import SwiftUI

import ChocofordUI
import SwiftyAlert
import SFSafeSymbols

struct ShareView: View {
    @Environment(\.dismiss) var dismiss
    @Environment(\.alertToast) var alertToast
    
    var sharedFile: File
    
    init(sharedFile: File) {
        self.sharedFile = sharedFile
    }
    
    enum Route: Hashable {
        case exportImage
        case exportFile
    }
    
    @State private var route: NavigationPath = .init()
    
    
    var body: some View {
        NavigationStack(path: $route) {
            VStack(spacing: 20) {
                Text("Choose an export target.")
                    .font(.largeTitle)

                
                HStack(spacing: 14) {
                    squareButton(title: "Image", icon: .photo) {
                        route.append(Route.exportImage)
                    }
                    
                    squareButton(title: "File", icon: .doc) {
                        route.append(Route.exportFile)
                    }
                    
                    squareButton(title: "Archive", icon: .archivebox) {
                        do {
                            try archiveAllFiles()
                        } catch {
                            alertToast(error)
                        }
                    }
                }
                
                
                Button {
                    dismiss()
                } label: {
                    HStack {
                        Spacer()
                        Text("Dismiss")
                        Spacer()
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
//            .navigationTitle("Share")
            .navigationDestination(for: Route.self) { route in
                switch route {
                    case .exportImage:
                        ExportImageView()
                    case .exportFile:
                        ExportFileView(file: sharedFile)
                }
            }
            .padding(.horizontal, 40)
            .toolbar(.hidden, for: .windowToolbar)
        }
        .frame(width: 400, height: 300)
        .visualEffect(material: .sidebar)
    }
    
    @MainActor @ViewBuilder
    private func squareButton(
        title: String,
        icon: SFSymbol,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            action()
        } label: {
            VStack {
                Image(systemSymbol: icon)
                    .resizable()
                    .scaledToFit()
                    .padding(.horizontal, 10)
                Text(title)
            }
        }
        .buttonStyle(ExportButtonStyle())
    }
}

struct ExportButtonStyle: PrimitiveButtonStyle {
    
    @State private var isHovered = false
    
    let size: CGFloat = 86
    
    func makeBody(configuration: Configuration) -> some View {
        PrimitiveButtonWrapper {
            configuration.trigger()
        } content: { isPressed in
            configuration.label
                .padding()
                .frame(width: size, height: size)
                .background {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(
                            isPressed ? AnyShapeStyle(Color.gray.opacity(0.4)) : AnyShapeStyle(isHovered ? .ultraThickMaterial : .regularMaterial)
                        )
                        .stroke(.separator, lineWidth: 0.5)
                        .animation(.default, value: isHovered)
                }
                .contentShape(Rectangle())
                .onHover { isHovered = $0 }
        }
    }
}

#if DEBUG
#Preview {
    ShareView(sharedFile: .preview)
        .environmentObject(ExportState())
}
#endif
