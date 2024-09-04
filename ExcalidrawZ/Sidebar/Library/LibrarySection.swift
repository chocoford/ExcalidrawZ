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
    
    @State private var isExpanded = true
    
    let columns = [
        GridItem(.flexible()),
        GridItem(.flexible()),
        GridItem(.flexible()),
    ]
    
    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            LazyVGrid(columns: columns) {
                ForEach(
                    (library.items?.allObjects as? [LibraryItem])?.sorted(by: {$0.createdAt ?? .distantPast < $1.createdAt ?? .distantPast}) ?? []
                ) { item in
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
        }
        .animation(.default, value: selections != nil)
    }
}

