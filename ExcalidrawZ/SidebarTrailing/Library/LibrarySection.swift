//
//  LibrarySectionContent
//  ExcalidrawZ
//
//  Created by Dove Zachary on 2024/9/4.
//

import SwiftUI

struct LibrarySectionContent: View {
    var allLibraries: FetchedResults<Library>
    var library: Library
    var selections: Binding<Set<LibraryItem>>?
    var searchQuery: String = ""
#if os(macOS)
    @State private var isExpanded = true
#elseif os(iOS)
    @State private var isExpanded = false
#endif

    @FetchRequest
    private var items: FetchedResults<LibraryItem>

    init(
        allLibraries: FetchedResults<Library>,
        library: Library,
        selections: Binding<Set<LibraryItem>>?,
        isExpanded: Bool = true,
        searchQuery: String = ""
    ) {
        self.allLibraries = allLibraries
        self.library = library
        self.selections = selections
        self.isExpanded = isExpanded
        self.searchQuery = searchQuery
        self._items = FetchRequest(
            sortDescriptors: [SortDescriptor(\.createdAt, order: .forward)],
            predicate: NSPredicate(format: "library = %@", library),
            animation: .default
        )
    }

    let columns = [
        GridItem(.flexible()),
        GridItem(.flexible()),
        GridItem(.flexible()),
    ]

    private var filteredItems: [LibraryItem] {
        guard !searchQuery.isEmpty else { return Array(items) }
        return items.filter { ($0.name ?? "").localizedCaseInsensitiveContains(searchQuery) }
    }

    @ViewBuilder
    var body: some View {
        if !searchQuery.isEmpty, filteredItems.isEmpty {
            EmptyView()
        } else {
            section
        }
    }

    @ViewBuilder
    private var section: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            LazyVGrid(columns: columns) {
                ForEach(filteredItems) { item in
                    LibraryItemView(item: item, inSelectionMode: selections != nil, libraries: allLibraries)
                        .transition(.asymmetric(insertion: .identity, removal: .scale.animation(.bouncy)))
                        .overlay(alignment: .bottomTrailing) {
                            if let selections {
                                let isSelected = selections.wrappedValue.contains(item)
                                let size: CGFloat = 18
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
                                .padding(2)
                                .frame(width: size, height: size)
                                .padding(4)
                            }
                        }
                        .simultaneousGesture(
                            TapGesture().onEnded { _ in
                                selections?.wrappedValue.insertOrRemove(item)
                            },
                            including: selections != nil ? .gesture : .subviews
                        )
                }
            }
        } label: {
            LibrarySectionHeader(allLibraries: allLibraries, library: library, inSelectionMode: selections != nil)
                .padding(.leading, 10)
        }
#if os(iOS)
        .disclosureGroupStyle(.leadingChevron)
#endif
        .animation(.default, value: selections != nil)
        .onChange(of: searchQuery) { newValue in
            // Auto-expand sections while filtering so matches are visible.
            if !newValue.isEmpty {
                isExpanded = true
            }
        }
    }
}

