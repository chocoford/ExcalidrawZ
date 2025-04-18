//
//  SwitchAppStoreVersionView.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 4/2/25.
//

import SwiftUI

import ChocofordUI
import SwiftyAlert

struct SwitchAppStoreVersionViewViewModifier: ViewModifier {
    @Binding var isPresented: Bool
    
    func body(content: Content) -> some View {
        content
#if os(macOS)
            .sheet(isPresented: $isPresented) {
                SwitchAppStoreVersionView()
                    .padding(40)
                    .frame(width: 660, height: 540)
                    .swiftyAlert()
            }
#endif
    }
}
#if os(macOS)
struct SwitchAppStoreVersionView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.alertToast) private var alertToast
    @State private var didArchive: Bool = false

    var body: some View {
        VStack {
            Text(.localizable(.paywallSwitchToAppStoreDialogTitle))
                .padding(.horizontal)
                .font(.title)
                .multilineTextAlignment(.center)
            
            Divider()
            
            VStack {
                Text("❗️❗️❗️\(String(localizable: .migrationAttentionTitle))❗️❗️❗️").font(.headline)
                Text(.localizable(.migrationAttentionContent))
                    .multilineTextAlignment(.center)
            }
            .padding(.vertical)
            .padding(.horizontal, 40)
            .background {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(hexString: "#f57c00").opacity(0.6))
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color(hexString: "#ffb74d"))
            }
            
            GeometryReader { geometry in
                let spacing: CGFloat = 10
                HStack(spacing: spacing) {
                    // Step 1
                    VStack(spacing: 20) {
                        Image(systemSymbol: .squareAndArrowUp)
                            .resizable()
                            .scaledToFit()
                            .frame(height: 30)
                        VStack(spacing: 10) {
                            Text(.localizable(.migrationSheetArchiveHeadling))
                                .font(.headline)
                            Text(.localizable(.migrationSheetArchiveDescription))
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxHeight: .infinity, alignment: .top)
                        AsyncButton { @MainActor in
                            do {
                                try archiveAllFiles(context: viewContext)
                            } catch {
                                alertToast(
                                    .init(
                                        displayMode: .hud,
                                        type: .regular,
                                        title: String(localizable: .archiveDoneWithErrorAlertTitle),
                                        subTitle: String(localizable: .archiveDoneWithErrorAlertSubtitle)
                                    )
                                )
                            }
                            didArchive = true
                        } label: {
                            Text(.localizable(.migrationSheetButtonArchive))
                        }
                    }
                    .padding()
                    .frame(width: (geometry.size.width - spacing) / 2, height: geometry.size.height)
                    .overlay(alignment: .topLeading) {
                        Image(systemSymbol: ._1Circle)
                            .resizable()
                            .scaledToFit()
                            .frame(height: 100)
                            .rotationEffect(.degrees(15))
                            .offset(x: -30, y: -30)
                            .foregroundStyle(.quaternary)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .background {
                        if #available(macOS 14.0, *) {
                            RoundedRectangle(cornerRadius: 12)
                                .fill(.thinMaterial)
                                .stroke(.separator, lineWidth: 0.5)
                        } else {
                            ZStack {
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(.thinMaterial)
                                
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(.separator, lineWidth: 0.5)
                            }
                        }
                    }
                    
                    // Step 2
                    VStack(spacing: 20) {
                        Image(systemSymbol: .squareAndArrowDown)
                            .resizable()
                            .scaledToFit()
                            .frame(height: 30)
                        VStack(spacing: 10) {
                            Text(.localizable(.paywallSwitchToAppStoreStep2Title))
                                .font(.headline)
                            
                            Text(.localizable(.paywallSwitchToAppStoreStep2Description))
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxHeight: .infinity, alignment: .top)
                        HStack {
                            Link(destination: URL(string: "https://apps.apple.com/app/excalidrawz/id6636493997")!) {
                                Text(.localizable(.generalButtonDownload))
                            }
                            .disabled(!didArchive)
                            .if(!didArchive) { content in
                                content
                                    .popoverHelp(.localizable(.migrationDownloadTooltip))
                            }
                        }
                    }
                    .padding()
                    .frame(width: (geometry.size.width - spacing) / 2, height: geometry.size.height)
                    .overlay(alignment: .topLeading) {
                        Image(systemSymbol: ._2Circle)
                            .resizable()
                            .scaledToFit()
                            .frame(height: 100)
                            .rotationEffect(.degrees(15))
                            .offset(x: -30, y: -30)
                            .foregroundStyle(.quaternary)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .background {
                        ZStack {
                            if #available(macOS 14.0, *) {
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(.thinMaterial)
                                    .stroke(.separator, lineWidth: 0.5)
                            } else {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(.thinMaterial)
                                    
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(.separator, lineWidth: 0.5)
                                }
                            }
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
            
            Button {
                dismiss()
            } label: {
                Text(.localizable(.generalButtonClose))
            }
            .buttonStyle(.borderless)
        }
    }
}

#Preview {
    SwitchAppStoreVersionView()
}
#endif
