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
        sortDescriptors: [.init(keyPath: \File.updatedAt, ascending: false)],
        predicate: NSPredicate(format: "inTrash == false"),
        animation: .default
    )
    private var files: FetchedResults<File>
    
    @FocusState private var inputTextFieldFocused: Bool
    
    @State private var inputText: String = ""
    
    @State private var selectedRecntlyFiles: Set<File> = []
    
    var body: some View {
        Color.clear
            .contentShape(Rectangle())
            .onTapGesture {
                inputTextFieldFocused = false
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
                
                TextField("", text: $inputText)
                    .textFieldStyle(.outlined(prepend: {
                        Image(systemSymbol: .magnifyingglass)
                            .foregroundStyle(.secondary)
                    }))
                    .focused($inputTextFieldFocused)
                    .frame(maxWidth: 500)
                    .background {
                        Color.clear
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
                                                    //                                        selectedRecntlyFiles.insert(file)
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
                    .opacity(inputText.isEmpty ? 1 : 0)
                }
            }
            .frame(maxWidth: 720)
            .padding(40)
            .overlayPreferenceValue(BoundsPreferenceKey.self) { key in
                if inputTextFieldFocused, let anchor = key["InputField"] {
                    GeometryReader { geomerty in
                        let rect = geomerty[anchor]
                        
                        SerachContent(withDismissButton: false)
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
#endif

