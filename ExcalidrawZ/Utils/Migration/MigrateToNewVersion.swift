//
//  MigrateToNewVersion.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 2024/8/14.
//

import SwiftUI

import ChocofordEssentials
import ChocofordUI

struct MigrateToNewVersionSheetViewModifier: ViewModifier {
    @Binding var showMigrateSheet: Bool
    
    init(isPresented: Binding<Bool>) {
        self._showMigrateSheet = isPresented
    }
    
    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $showMigrateSheet) {
                MigrateToNewVersionSheetView()
            }
            .onAppear {
                if !appVersion.contains("alpha"),
                    !appVersion.contains("beta"),
                   Bundle.main.bundleIdentifier == "com.chocoford.ExcalidrawZ" || Bundle.main.bundleIdentifier == "com.chocoford.ExcalidrawZ-Debug" {
                    showMigrateSheet = !UserDefaults.standard.bool(forKey: "PreventShowMigrationSheet")
                }
            }
    }
}

fileprivate struct MigrateToNewVersionSheetView: View {
    @Environment(\.dismiss) var dismiss
    @State private var window: NSWindow?
    
    @AppStorage("PreventShowMigrationSheet") var notShowAgain = false
    
    var body: some View {
        VStack(spacing: 20) {
            Text(.localizable(.migrationSheetTitle))
                .font(.largeTitle)
            
            Text(.localizable(.migrationSheetBody))
            
            GeometryReader { geometry in
                let spacing: CGFloat = 10
                HStack(spacing: spacing) {
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
                            try archiveAllFiles()
                        } label: {
                            Text(.localizable(.migrationSheetButtonArchive))
                        }
                    }
                    .padding()
                    .frame(width: (geometry.size.width - spacing) / 2, height: geometry.size.height)
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
                    
                    VStack(spacing: 20) {
                        Image(systemSymbol: .squareAndArrowDown)
                            .resizable()
                            .scaledToFit()
                            .frame(height: 30)
                        VStack(spacing: 10) {
                            Text(.localizable(.migrationSheetDownloadHeadline))
                                .font(.headline)
                            
                            Text(.localizable(.migrationSheetDownloadDescription))
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxHeight: .infinity, alignment: .top)
                        HStack {
                            Link(destination: URL(string: "https://github.com/chocoford/ExcalidrawZ?tab=readme-ov-file")!) {
                                Text("Non-AppStore")
                            }
                            Link(destination: URL(string: "https://github.com/chocoford/ExcalidrawZ?tab=readme-ov-file")!) {
                                Text("AppStore")
                            }
                        }
                    }
                    .padding()
                    .frame(width: (geometry.size.width - spacing) / 2, height: geometry.size.height)
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
            Text(.localizable(.migrationSheetTips))
                .padding(.horizontal, 40)
              
            HStack {
                Toggle(isOn: $notShowAgain) {
                    Text(.localizable(.migrationSheetButtonNeverShow))
                }
                .opacity(0)
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Text(.localizable(.migrationSheetButtonClose))
                }
                .controlSize(.large)
                .buttonStyle(.borderless)
                Spacer()
                Toggle(isOn: $notShowAgain) {
                    Text(.localizable(.migrationSheetButtonNeverShow))
                }
            }
            .padding(.horizontal, 20)
        }
        .multilineTextAlignment(.center)
        .padding()
        .frame(width: 600, height: 450)
        .modifier(MigrateToNewVersionSheetBackgroundModifier())
        .bindWindow($window)
        .onAppear {
            window?.backgroundColor = .clear
        }
    }
}

struct MigrateToNewVersionSheetBackgroundModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 13.0, *) {
            content
                .background(Color.accentColor.gradient)
                .preferredColorScheme(.dark)
        } else {
            content
                .background(Color.accentColor)
                .preferredColorScheme(.dark)
        }
    }
}


#Preview {
    MigrateToNewVersionSheetView()
}
