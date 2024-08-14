//
//  MigrateToNewVersion.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 2024/8/14.
//

import SwiftUI

import ChocofordUI

struct MigrateToNewVersionSheetViewModifier: ViewModifier {
    @State private var showMigrateSheet = false
    
    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $showMigrateSheet) {
                MigrateToNewVersionSheetView()
            }
            .onAppear {
                showMigrateSheet = !UserDefaults.standard.bool(forKey: "PreventShowMigrationSheet")
            }
    }
}

fileprivate struct MigrateToNewVersionSheetView: View {
    @Environment(\.dismiss) var dismiss
    @State private var window: NSWindow?
    
    @AppStorage("PreventShowMigrationSheet") var notShowAgain = false
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Migrate to new version")
                .font(.largeTitle)
            
            Text("ExcalidrawZ has reached a new milestone—the official release of version 1.0. The new version has changed the application ID, so you will need to manually download it and migrate your existing files.")
            
            GeometryReader { geometry in
                let spacing: CGFloat = 10
                HStack(spacing: spacing) {
                    VStack(spacing: 20) {
                        Image(systemSymbol: .squareAndArrowUp)
                            .resizable()
                            .scaledToFit()
                            .frame(height: 30)
                        VStack(spacing: 10) {
                            Text("Archive all files")
                                .font(.headline)
                            Text("Export all files and import them to the new version of ExcalidrawZ.")
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxHeight: .infinity, alignment: .top)
                        AsyncButton { @MainActor in
                            try archiveAllFiles()
                        } label: {
                            Text("Archive")
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
                            Text("Download the new ExcalidrawZ")
                                .font(.headline)
                            
                            Text("Two versions of ExcalidrawZ are available: the App Store version and the non-App Store version.")
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
            Text("You can still continue to use the current app, and your data remains safe, but future updates will not be pushed here.")
                .padding(.horizontal, 40)
              
            HStack {
                Toggle(isOn: $notShowAgain) {
                    Text("Don't show again")
                }
                .opacity(0)
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Text("Close")
                }
                .controlSize(.large)
                .buttonStyle(.borderless)
                Spacer()
                Toggle(isOn: $notShowAgain) {
                    Text("Don't show again")
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
