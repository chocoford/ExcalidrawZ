//
//  DebugInfoView.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 4/14/25.
//

import SwiftUI

import ChocofordUI

#if DEBUG
@available(macOS 15.0, iOS 18.0, *)
struct DebugButton: View {
    @State private var isDebugSheetPresented = false
    
    var body: some View {
        Button {
            isDebugSheetPresented.toggle()
        } label: {
            Label("Debug", systemSymbol: .ladybug)
        }
        .sheet(isPresented: $isDebugSheetPresented) {
            DebugInfoView()
                .frame(width: 800, height: 500)
                .overlay(alignment: .topTrailing) {
                    Button {
                        isDebugSheetPresented.toggle()
                    } label: {
                        Image(systemSymbol: .xmarkCircleFill)
                            .resizable()
                            .scaledToFit()
                            .frame(height: 20)
                    }
                    .buttonStyle(.borderless)
                    .padding(20)
                }
        }
    }
}


@available(macOS 15.0, iOS 18.0, *)
struct DebugInfoView: View {
    @Environment(\.managedObjectContext) private var viewContext
    
    @EnvironmentObject private var fileState: FileState
    
    enum Tabs {
        case fileContent
    }
    
    @State private var selectedTab: Tabs = .fileContent
    
    var currentFile: File? {
        fileState.currentFile
    }
    
    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("File Content", systemImage: "play", value: .fileContent) {
                if let file = fileState.currentFile,
                   let excalidrawFile = try? ExcalidrawFile.init(
                    from: file.objectID,
                    context: viewContext
                ) {
                    FileInfoDebugView(
                        file: excalidrawFile
                    )
                } else {
                    Text("No file info")
                        .font(.largeTitle)
                        .foregroundStyle(.placeholder)
                }
            }
            // More tabs...
        }
        .tabViewStyle(.sidebarAdaptable)
    }
}


#Preview {
    if #available(macOS 15.0, iOS 18.0, *) {
        DebugInfoView()
    }
}
#endif
