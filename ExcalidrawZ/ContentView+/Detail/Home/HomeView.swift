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

//protocol RecentlyHomeFile {
//    var lastVisitedAt: Date? { get }
//}
//
//extension File: RecentlyHomeFile {
//    var lastVisitedAt: Date? { visitedAt }
//}
//extension CollaborationFile: RecentlyHomeFile {
//    var lastVisitedAt: Date? { visitedAt }
//}

struct HomeView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.scenePhase) private var scenePhase
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
    
    @FetchRequest(
        sortDescriptors: [],
        animation: .default
    )
    private var localFolders: FetchedResults<LocalFolder>
    
    // @State private var localFiles: [URL] = []
    
    @FetchRequest(
        sortDescriptors: [
            .init(keyPath: \File.updatedAt, ascending: false),
            .init(keyPath: \File.visitedAt, ascending: false)
        ],
        animation: .default
    )
    private var collaborationFiles: FetchedResults<CollaborationFile>
    
    @State private var recentlyFiles: [FileState.ActiveFile] = []
    
    @State private var isSearchPresented: Bool = false
    
    @State private var inputText: String = ""
    
    @State private var selectedRecntlyFiles: Set<FileState.ActiveFile> = []
    
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
                .contentShape(Rectangle())
                .hoverCursor(.horizontalText)
                .simultaneousGesture(TapGesture().onEnded {
                    isSearchPresented.toggle()
                })
                .background {
                    ZStack {
                        if #available(macOS 26.0, iOS 26.0, *) {
                            RoundedRectangle(cornerRadius: 16)
                                .fill(Color.textBackgroundColor)
                                .stroke(Color.separatorColor, lineWidth: 0.5)
                                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 16))
                        } else {
                            RoundedRectangle(cornerRadius: 16)
                                .fill(Color.textBackgroundColor)
                                .shadow(
                                    color: colorScheme == .light
                                    ? Color.gray.opacity(0.33)
                                    : Color.black.opacity(0.33),
                                    radius: 10,
                                )
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(Color.separatorColor, lineWidth: 0.5)
                            
                        }
                    }
                    .compositingGroup()
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
                                    ForEach(recentlyFiles) { file in
                                        FileHomeItemView(
                                            file: file,
                                            isSelected: Binding {
                                                selectedRecntlyFiles.contains(file)
                                            } set: { val in
                                                if val {
                                                    selectedRecntlyFiles = [file]
                                                } else {
                                                    selectedRecntlyFiles.remove(file)
                                                }
                                            },
                                        )
                                        .frame(width: 200)
                                    }
                                }
                                .padding(10)
                            }
                            .offset(x: -10)
                        }
                        .onHover { isHovered in
                            if isHovered { getRecentlyFiles() }
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
                            
                            SerachContent(withDismissButton: false, source: .normal) {
                                isSearchPresented = false
                            }
                            .background {
                                ZStack {
                                    if #available(macOS 26.0, iOS 26.0, *) {
                                        RoundedRectangle(cornerRadius: 16)
                                            .fill(Color.textBackgroundColor)
                                            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 16))
                                    } else {
                                        RoundedRectangle(cornerRadius: 16)
                                            .fill(Color.textBackgroundColor)
                                    }
                                }
                                .shadow(
                                    color: colorScheme == .light
                                    ? .gray.opacity(0.33)
                                    : .black.opacity(0.33),
                                    radius: 4,
                                    y: 0
                                )
                                .transition(.opacity)
                            }
                            .frame(width: rect.width, height: 500)
                            .offset(x: rect.minX, y: rect.minY)
                            .animation(.bouncy, value: rect)
                        }
                    }
                }
            }
            .onChange(of: scenePhase) { _ in
                getRecentlyFiles()
            }
            .onAppear {
                getRecentlyFiles()
            }
        }
    }
    
    private func getRecentlyFiles() {
        // Recently means visited in the last 7 days
        // let calendar = Calendar.current
        // let sevenDaysAgo = calendar.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        
        var allDatedFiles: [FileState.ActiveFile : Date] = [:]
        
        // files
        files.forEach { file in
            allDatedFiles[.file(file)] = file.visitedAt ?? file.updatedAt ?? file.createdAt ?? .distantPast
        }
        
        // Local files
        for folder in localFolders {
            do {
                let filesAndModificationDates: [(URL, Date)] = try folder.getFiles(
                    deep: true,
                    properties: [.contentModificationDateKey, .creationDateKey]
                ) { url in
                    let modifiedDate = try url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate ?? .distantPast
                    let creationDate = try url.resourceValues(forKeys: [.creationDateKey]).creationDate ?? .distantPast
                    return (url, max(modifiedDate, creationDate))
                }
                
                filesAndModificationDates.forEach { (url, date) in
                    allDatedFiles[.localFile(url)] = date
                }
            } catch {
                
            }
        }
        
        // Collaboration files
        collaborationFiles.forEach { file in
            allDatedFiles[.collaborationFile(file)] = file.visitedAt ?? file.updatedAt ?? file.createdAt ?? .distantPast
        }
        
        
        let sortedAllFiles = allDatedFiles.sorted(by: {
            $0.value > $1.value
        }).map {$0.key}
        
        self.recentlyFiles = Array(sortedAllFiles.prefix(20))
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

