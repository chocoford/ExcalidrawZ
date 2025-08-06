//
//  HomeView.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 8/3/25.
//

import SwiftUI
import ChocofordUI

struct BoundsPreferenceKey: PreferenceKey {
    static var defaultValue: [String : Anchor<CGRect>] = [:]
    
    static func reduce(value: inout [String : Anchor<CGRect>], nextValue: () -> [String : Anchor<CGRect>]) {
        value.merge(nextValue()) { $1 }
    }
    
}

struct HomeView: View {
    @EnvironmentObject private var fileState: FileState
    
    @FetchRequest(
        sortDescriptors: [
            .init(keyPath: \File.updatedAt, ascending: false),
            .init(keyPath: \File.visitedAt, ascending: false)
        ],
        predicate: NSPredicate(format: "inTrash == false"),
        animation: .default
    )
    private var files: FetchedResults<File>
    
    @State private var isSearchPresented: Bool = false
    
    @State private var inputText: String = ""
    
    @State private var selectedRecntlyFiles: Set<File> = []
    
    var body: some View {
        Color.clear
            .contentShape(Rectangle())
            .onTapGesture {
                isSearchPresented = false
                selectedRecntlyFiles.removeAll()
            }
            .overlay {
                content()
            }
    }
    
    @MainActor @ViewBuilder
    private func content() -> some View {
        ZStack {
            VStack(spacing: 30) {
                
                Text("Welcome to ExcalidrawZ")
                    .font(.largeTitle)
                
                HStack(spacing: 8) {
                    Image(systemSymbol: .magnifyingglass)
                    Text(.localizable(.searchFieldPropmtText))
                        .foregroundStyle(.secondary.opacity(0.4))
                    Spacer()
                }
                .padding(10)
                .frame(maxWidth: 500)
                .hoverCursor(.iBeam)
                .contentShape(Rectangle())
                .simultaneousGesture(TapGesture().onEnded {
                    isSearchPresented.toggle()
                })
                .background {
                    ZStack {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.textBackgroundColor)
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.separatorColor, lineWidth: 0.5)
                    }
                    .compositingGroup()
                    .shadow(radius: 0.5, y: 0.5)
                    .padding(1)
                    .anchorPreference(
                        key: BoundsPreferenceKey.self,
                        value: .bounds
                    ) {
                        ["InputField" : $0]
                    }
                }
                
                
                ZStack {
                    VStack(spacing: 30) {
                        VStack(alignment: .leading) {
                            HStack {
                                Image(systemSymbol: .clock)
                                Text("Recently visited")
                            }
                            .font(.subheadline)
                            
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 10) {
                                    ForEach(files.prefix(10)) { file in
                                        FileHomeItemView(
                                            isSelected: Binding {
                                                selectedRecntlyFiles.contains(file)
                                            } set: { val in
                                                if val {
                                                    selectedRecntlyFiles = [file]
                                                } else {
                                                    selectedRecntlyFiles.remove(file)
                                                }
                                            },
                                            file: file
                                        )
                                        .frame(width: 200)
                                    }
                                }
                                .padding(10)
                            }
                            .offset(x: -10)
                        }
                        
                        VStack(alignment: .leading) {
                            HStack {
                                Text("Tips")
                                Spacer()
                            }
                            
                            VStack {
                                HStack {
                                    Rectangle().fill(.secondary)
                                    Rectangle().fill(.secondary)
                                }
                                .frame(height: 200)
                            }
                        }
                    }
                    // .opacity(inputText.isEmpty ? 1 : 0)
                }
            }
            .frame(maxWidth: 720)
            .padding(40)
            .overlayPreferenceValue(BoundsPreferenceKey.self) { key in
                if isSearchPresented, let anchor = key["InputField"] {
                    ZStack {
                        Color.clear
                            .contentShape(Rectangle())
                            .onTapGesture {
                                isSearchPresented = false
                            }
                        GeometryReader { geomerty in
                            let rect = geomerty[anchor]
                            
                            SerachContent(withDismissButton: false) {
                                isSearchPresented = false
                            }
                            .background {
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(.background)
                                    .shadow(radius: 1, y: 2)
                            }
                            .frame(width: rect.width, height: 500)
                            .offset(x: rect.minX, y: rect.minY)
                            .animation(.bouncy, value: rect)
                        }
                    }
                }
            }
        }
    }
}

#if DEBUG
private struct APreviewView: View {
    var body: some View {
        VStack {
            Image(systemName: "globe")
                .imageScale(.large)
                .foregroundStyle(.tint)
            Text("Hello, world!")
        }
        .padding()
    }
}

#Preview {
    APreviewView()
        .environmentObject(FileState())
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
}
#endif // DEBUG

