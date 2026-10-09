//
//  LibrarySectionContent
//  ExcalidrawZ
//
//  Created by Dove Zachary on 2024/9/4.
//

import SwiftUI
import CoreData
import ChocofordUI

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
        self._isExpanded = State(initialValue: isExpanded)
        self.searchQuery = searchQuery
        self._items = FetchRequest(
            sortDescriptors: [SortDescriptor(\.createdAt, order: .forward)],
            predicate: NSPredicate(format: "library = %@", library),
            animation: .default
        )
    }

    private let columnCount = 3
    private let itemSpacing: CGFloat = 8

    private var filteredItems: [LibraryItem] {
        guard !searchQuery.isEmpty else { return Array(items) }
        return items.filter { ($0.name ?? "").localizedCaseInsensitiveContains(searchQuery) }
    }

    private var itemRows: [ItemRow] {
        let items = filteredItems
        return stride(from: 0, to: items.count, by: columnCount).map { startIndex in
            let endIndex = min(startIndex + columnCount, items.count)
            let rowItems = Array(items[startIndex..<endIndex])
            return ItemRow(
                id: rowItems.first?.objectID ?? library.objectID,
                items: rowItems
            )
        }
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
            VStack(spacing: itemSpacing) {
                ForEach(itemRows) { row in
                    HStack(spacing: itemSpacing) {
                        ForEach(row.items) { item in
                            libraryItemCell(item)
                        }

                        ForEach(0..<max(0, columnCount - row.items.count), id: \.self) { _ in
                            Color.clear
                                .frame(height: 0)
                                .frame(maxWidth: .infinity)
                        }
                    }
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
        .watch(value: searchQuery) { newValue in
            // Auto-expand sections while filtering so matches are visible.
            if !newValue.isEmpty {
                isExpanded = true
            }
        }
    }

    @ViewBuilder
    private func libraryItemCell(_ item: LibraryItem) -> some View {
        LibraryItemView(item: item, inSelectionMode: selections != nil, libraries: allLibraries)
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
            .frame(maxWidth: .infinity)
    }

    private struct ItemRow: Identifiable {
        let id: NSManagedObjectID
        let items: [LibraryItem]
    }
}
