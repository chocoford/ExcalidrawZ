//
//  LibraryImportSheetView.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 2024/9/3.
//

import SwiftUI

struct ExcalidrawLibraryImportSheetView: View {
    @Environment(\.dismiss) var dismiss
    @Environment(\.alertToast) var alertToast
    
    var libraries: [ExcalidrawLibrary]
    
    @State private var selectedItems = Set<ExcalidrawLibrary.Item>()
    
    var body: some View {
        VStack(spacing: 10) {
            HStack(alignment: .lastTextBaseline) {
                Toggle("", isOn: .constant(false))
                    .opacity(0)
                Spacer()
                Text(.localizable(.librariesImportTitle))
                    .font(.largeTitle)
                Spacer()
                Toggle(
                    .localizable(.librariesImportSelectAll),
                    isOn: Binding {
                        libraries.allSatisfy({$0.libraryItems.allSatisfy({selectedItems.contains($0)})})
                    } set: { isOn in
                        if isOn {
                            for library in libraries {
                                for item in library.libraryItems {
                                    selectedItems.insert(item)
                                }
                            }
                        } else {
                            for library in libraries {
                                for item in library.libraryItems {
                                    selectedItems.remove(item)
                                }
                            }
                        }
                    }
                )
            }
            
            ScrollView {
                LazyVGrid(columns: [
                    GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())
                ], pinnedViews: [.sectionHeaders]) {
                    ForEach(libraries, id: \.self) { library in
                        Section {
                            ForEach(library.libraryItems, id: \.id) { item in
                                Button {
                                    if selectedItems.contains(item) {
                                        selectedItems.remove(item)
                                    } else {
                                        selectedItems.insert(item)
                                    }
                                } label: {
                                    HStack(spacing: 6) {
                                        LibraryItemContentView(
                                            item: ExcalidrawLibrary(
                                                id: library.id,
                                                name: library.name,
                                                type: library.type,
                                                version: library.version,
                                                source: library.source,
                                                libraryItems: [item]
                                            ),
                                            size: 40
                                        )
                                        VStack(alignment: .leading) {
                                            Text(item.name)
                                            Text(item.createdAt.formatted(.dateTime.year().month().day()))
                                                .font(.footnote)
                                                .foregroundStyle(.secondary)
                                        }
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                        
                                        Spacer()
                                        
                                        let size: CGFloat = 18
                                        let isSelected = selectedItems.contains(item)
                                        ZStack {
                                            if isSelected {
                                                Circle().fill(.green)
                                                Circle().stroke(.green)
                                            } else {
                                                Circle().stroke(.primary)
                                            }
                                            
                                            Image(systemSymbol: .checkmark)
                                                .resizable()
                                                .scaledToFit()
                                                .font(.body.bold())
                                                .padding(3)
                                                .foregroundStyle(isSelected ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
                                        }
                                        .animation(.easeOut(duration: 0.15), value: isSelected)
                                        .padding(2)
                                        .frame(width: size, height: size)
                                    }
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                        } header: {
                            VStack(spacing: 0) {
                                HStack {
                                    Text(library.name ?? "Untitled")
                                    Text(.localizable(.librariesImportLibraryItemsCount(library.libraryItems.count)))
                                        .foregroundStyle(.secondary)
                                        .font(.footnote)
                                    
                                    Spacer()
                                    
                                    Toggle(
                                        .localizable(.librariesImportLibrarySelectAll),
                                        isOn: Binding {
                                            library.libraryItems.allSatisfy{ selectedItems.contains($0) }
                                        } set: { isOn in
                                            if isOn {
                                                for item in library.libraryItems {
                                                    selectedItems.insert(item)
                                                }
                                            } else {
                                                for item in library.libraryItems {
                                                    selectedItems.remove(item)
                                                }
                                            }
                                        }
                                    )
                                    .toggleStyle(.checkbox)
                                }
                                Divider()
                            }
                            .padding(.top, 12)
                            .background(.regularMaterial)
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.bottom)
            }
            .frame(minHeight: 300, maxHeight: 600)
            .background {
                let roundedRectangle = RoundedRectangle(cornerRadius: 12)
                roundedRectangle.stroke(.separator, lineWidth: 0.5)
                roundedRectangle.fill(.regularMaterial)
            }
            
            HStack {
                if !selectedItems.isEmpty {
                    Text(.localizable(.librariesImportSelectionsCount(selectedItems.count)))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                Button {
                    dismiss()
                } label: {
                    Text(.localizable(.librariesImportButtonCancel))
                        .frame(width: 80)
                }
                .buttonStyle(.borderless)
                
                Button {
                    importSelectedLibraries()
                } label: {
                    Text(.localizable(.librariesImportButtonImport))
                        .frame(width: 80)
                }
                .buttonStyle(.borderedProminent)
                .disabled(selectedItems.isEmpty)
            }
            .controlSize(.large)
        }
        .padding(.vertical, 20)
        .padding(.horizontal, 40)
        .onAppear {
            selectedItems = Set(
                libraries.flatMap {
                    $0.libraryItems
                }
            )
        }
    }
    
    func importSelectedLibraries() {
        let context = PersistenceController.shared.container.newBackgroundContext()
        
        context.perform {
            let selection: [ExcalidrawLibrary : [ExcalidrawLibrary.Item]] = {
                var results: [ExcalidrawLibrary : [ExcalidrawLibrary.Item]] = libraries.filter({
                    $0.libraryItems.contains(where: {selectedItems.contains($0)})
                }).map {
                    [$0 : []]
                }.merged()
                
                for selectedItem in selectedItems {
                    if let library = results.first(where: {$0.key.libraryItems.contains(selectedItem)})?.key {
                        results[library]?.append(selectedItem)
                    }
                }
                
                return results
            }()
            do {
                for libraryData in selection.keys {
                    let library = Library(context: context)
                    library.id = UUID()
                    library.createdAt = Date()
                    library.name = libraryData.name
                    library.source = libraryData.source
                    library.version = Int32(libraryData.version)
                    library.items = []
                    
                    for item in selection[libraryData] ?? [] {
                        let libraryItem = LibraryItem(context: context)
                        libraryItem.id = item.id
                        libraryItem.name = item.name
                        libraryItem.createdAt = item.createdAt
                        libraryItem.elements = try JSONEncoder().encode(item.elements)
                        libraryItem.library = library
                    }
                }
                try context.save()
            } catch {
                alertToast(error)
            }
        }
        dismiss()
    }
}

#if DEBUG
#Preview {
    ExcalidrawLibraryImportSheetView(libraries: [.preview])
        .frame(width: 600)
        .environmentObject(ExportState())
}
#endif
