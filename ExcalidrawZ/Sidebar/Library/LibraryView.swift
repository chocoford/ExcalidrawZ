//
//  LibraryView.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 2024/9/2.
//

import SwiftUI

import SFSafeSymbols
import ChocofordEssentials
import ChocofordUI
import SVGView

struct LibraryView: View {
    @EnvironmentObject var exportState: ExportState
    
    @Binding var isPresented: Bool
    
    let columns = [
        GridItem(.flexible()),
        GridItem(.flexible()),
//        GridItem(.flexible()),
        GridItem(.flexible()),
    ]
    
    // each library contains one library item...
    @State private var libraries: [ExcalidrawLibrary] = []
    @State private var image: Image?
    @State private var svgImage: SVGView?
    
    var body: some View {
        VStack {
            ScrollView {
                LazyVGrid(columns: columns) {
                    ForEach(libraries, id: \.libraryItems[0].id) { item in
                        LibraryItemView(
                            item: item
                        )
                    }
                }
                .padding(.horizontal, 10)
            }
        }
        .toolbar {
            ToolbarItem(placement: .automatic) {
                if isPresented {
                    FileImporterButton(
                        types: [.init(filenameExtension: "excalidrawlib")!],
                        allowMultiple: true
                    ) { urls in
                        for url in urls {
                            _ = url.startAccessingSecurityScopedResource()
                            let data = try Data(contentsOf: url)
                            let library = try JSONDecoder().decode(ExcalidrawLibrary.self, from: data)
                            self.libraries.append(contentsOf: library.libraryItems.map {
                                ExcalidrawLibrary(type: library.type, version: library.version, source: library.source, libraryItems: [$0])
                            })
                            url.stopAccessingSecurityScopedResource()
                        }
                    } label:  {
                        Label("Import", systemSymbol: .squareAndArrowDown)
                    }
                }
            }
            
            /// This is the key to make sidebar toggle at the right side.
            ToolbarItem(placement: .status) {
                if isPresented {
                    Text("Library")
                        .foregroundStyle(.secondary)
                        .font(.headline)
                } else {
                    Color.clear
                        .frame(width: 1)
                }
            }
            
            ToolbarItem(placement: .automatic) {
                if #available(macOS 14.0, *) {
                    Button {
                        isPresented.toggle()
                    } label: {
                        Label("Library", systemSymbol: .sidebarRight)
                    }
//                    .buttonStyle(.accessoryBar)
                } else {
                    Button {
                        isPresented.toggle()
                    } label: {
                        Label("Library", systemSymbol: .sidebarRight)
                    }
                    .buttonStyle(.text)
                }
            }
        }
    }
}


struct ExcalidrawLibrary: Codable {
    var type: String
    var version: Int
    var source: String
    var libraryItems: [Item]
    
    struct Item: Codable {
        enum Status: String, Codable {
            case published = "published"
        }
        
        var id: String
        var status: Status
        var createdAt: Date
        var name: String
        var elements: [ExcalidrawElement]
        
        enum CodingKeys: String, CodingKey {
            case id, status, name, elements
            case createdAt = "created"
        }
        
        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            
            self.id = try container.decode(String.self, forKey: .id)
            self.status = try container.decode(Status.self, forKey: .status)
            let ts = try container.decode(Int.self, forKey: .createdAt)
            self.createdAt = Date(timeIntervalSince1970: Double(ts) / 1000)
            self.name = try container.decode(String.self, forKey: .name)
            self.elements = try container.decode([ExcalidrawElement].self, forKey: .elements)
        }
        
        func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(self.id, forKey: .id)
            try container.encode(self.status, forKey: .status)
            try container.encode(Int(self.createdAt.timeIntervalSince1970 * 1000), forKey: .createdAt)
            try container.encode(self.name, forKey: .name)
            try container.encode(self.elements, forKey: .elements)
        }
    }
}

#if DEBUG

struct LibraryPreviewView: View {
    var body: some View {
        if #available(macOS 14.0, *) {
            NavigationSplitView {
                
            } detail: {
                
            }
            .inspector(isPresented: .constant(true)) {
                LibraryView(isPresented: .constant(true))
            }
        } else {
            Color.clear
        }
    }
}

#Preview {
    LibraryPreviewView()
}
#endif
