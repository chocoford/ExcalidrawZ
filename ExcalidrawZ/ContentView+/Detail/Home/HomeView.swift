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
    
    @State private var isSearchPresented: Bool = false
    
    @State private var inputText: String = ""

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 30) {
                 Color.clear.frame(height: 40)
                
                Text(.localizable(.homeTitle))
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
                        
                        RecentlyFilesSection()

#if DEBUG || DEV
                        // TemplatesSection()
#endif
                        
                        HomeTipsSection()
                    }
                }
            }
            // .frame(maxWidth: 720)
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
            .frame(maxWidth: .infinity)
            .modifier(ExcalidrawLibraryDropHandler())
            .modifier(ItemDropFallbackModifier())
            .background {
                Color.clear.contentShape(Rectangle())
                    .onTapGesture {
                        fileState.resetSelections()
                    }
            }
        }
        .scrollClipDisabledIfAvailable()
    }
    
}

struct RecentlyFilesProvider: View {
    @Environment(\.scenePhase) private var scenePhase

    var content: ([FileState.ActiveFile]) -> AnyView
    
    init<Content: View>(
        @ViewBuilder content: @escaping ([FileState.ActiveFile]) -> Content
    ) {
        self.content = { files in
            AnyView(content(files))
        }
    }
    
    @FetchRequest(
        sortDescriptors: [
            .init(keyPath: \File.visitedAt, ascending: false),
            .init(keyPath: \File.updatedAt, ascending: false),
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
    
    @FetchRequest(
        sortDescriptors: [
            .init(keyPath: \File.visitedAt, ascending: false),
            .init(keyPath: \File.updatedAt, ascending: false),
        ],
        animation: .default
    )
    private var collaborationFiles: FetchedResults<CollaborationFile>
    
    
    @State private var recentlyFiles: [FileState.ActiveFile] = []
    
    var body: some View {
        content(recentlyFiles)
            .onHover { isHovered in
                if isHovered { getRecentlyFiles() }
            }
            .onChange(of: scenePhase) { _ in
                getRecentlyFiles()
            }
            .onAppear {
                getRecentlyFiles()
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

private struct RecentlyFilesSection: View {
    
    init() {}
    
    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                Image(systemSymbol: .clock)
                Text(.localizable(.homeRecentlyVisitedTitle))
            }
            .font(.headline)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    RecentlyFilesProvider { recentlyFiles in
                        ForEach(recentlyFiles) { file in
                            FileHomeItemView(
                                file: file,
                                canMultiSelect: false
                            )
                            .frame(width: 200)
                        }
                        
                        if recentlyFiles.isEmpty {
                            ForEach(0..<10) { _ in
                                RoundedRectangle(cornerRadius: FileHomeItemView.roundedCornerRadius)
                                    .fill(.secondary.opacity(0.5))
                                    .frame(width: 200, height: 200 * 0.6)
                            }
                        }
                    }
                }
                .padding(10)
            }
            .offset(x: -10)
            .scrollClipDisabledIfAvailable()
//            .overlay {
//                RecentlyFilesProvider { recentlyFiles in
//                    if recentlyFiles.isEmpty {
//                        Text("No recently files...")
//                            .font(.footnote)
//                            .foregroundStyle(.secondary)
//                    }
//                }
//            }
        }
    }

}

private struct TemplatesSection: View {
    var body: some View {
        VStack {
            HStack {
                Text("Templates")
                Spacer()
                Button {
                    
                } label: {
                    Text("Show All")
                }
            }
            
            ScrollView(.horizontal) {
                
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

