//
//  FileHomeView.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 8/3/25.
//

import SwiftUI
import ChocofordUI

struct FileHomeView: View {
    @EnvironmentObject var fileState: FileState

    var group: Group
    
    @FetchRequest
    private var files: FetchedResults<File>
    @FetchRequest
    private var childGroups: FetchedResults<Group>
    
    init(group: Group) {
        self.group = group
        self._files = FetchRequest<File>(
            sortDescriptors: [NSSortDescriptor(keyPath: \File.name, ascending: true)],
            predicate: group.groupType == .trash
            ? NSPredicate(format: "inTrash == true")
            : NSPredicate(format: "inTrash == false AND group == %@", group),
        )
        
        self._childGroups = FetchRequest<Group>(
            sortDescriptors: [NSSortDescriptor(keyPath: \Group.name, ascending: true)],
            predicate: group.groupType == .trash
            ? NSPredicate(format: "false")
            : NSPredicate(format: "parent == %@", group)
        )
    }
    
    @State private var selection: NSManagedObjectID?
    
    @State private var scrollViewHeight: CGFloat = 0
    @State private var contentHeight: CGFloat = 0
    
    var body: some View {
        ZStack {
            if #available(macOS 13.0, iOS 15.0, *) {
                content()
                    .scrollContentBackground(.hidden)
            } else {
                content()
            }
        }
        .background {
            // Not working
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture {
                    print("On Tap")
                }
        }
        .readHeight($scrollViewHeight)
    }
    
    
    @MainActor @ViewBuilder
    private func content() -> some View {
        ScrollView {
            VStack(spacing: 0) {
                VStack(spacing: 30) {
                    // Header
                    VStack {
                        HStack {
                            Text(group.name ?? String(localizable: .generalUntitled))
                                .font(.title)
                            
                            Spacer()
                            
                            // Toolbar
                            HStack {
                                Menu {
                                    
                                } label: {
                                    Image(systemSymbol: .ellipsisCircle)
                                }
                                .fixedSize()
                                .menuIndicator(.hidden)
                                .buttonStyle(.borderless)
                            }
                        }
                    }
                    
                    // Groups
                    LazyVGrid(columns: [.init(.adaptive(minimum: 260, maximum: 320), spacing: 20)], spacing: 20) {
                        ForEach(childGroups) { group in
                            HomeFolderItemView(
                                isSelected: selection == group.objectID,
                                name: group.name ?? String(localizable: .generalUntitled),
                                itemsCount: group.files?.count ?? 0
                            )
                            .simultaneousGesture(TapGesture(count: 2).onEnded {
                                fileState.currentGroup = group
                                fileState.expandToGroup(group.objectID)
                            })
                            .simultaneousGesture(TapGesture().onEnded {
                                selection = group.objectID
                            })
                        }
                    }
                    
                    // Files
                    LazyVGrid(columns: [.init(.adaptive(minimum: 260, maximum: 320), spacing: 20)], spacing: 20) {
                        ForEach(files) { file in
                            FileHomeItemView(
                                isSelected: Binding {
                                    selection == file.objectID
                                } set: { val in
                                    if val {
                                        selection = file.objectID
                                    }
                                },
                                file: file
                            )
                        }
                    }
                    
                }
                .padding(30)
                .background {
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture {
                            selection = nil
                        }
                }
                .readHeight($contentHeight)
                
                Color.clear
                    .frame(height: max(0, scrollViewHeight - contentHeight))
                    .contentShape(Rectangle())
                    .onTapGesture {
                        selection = nil
                    }
            }
        }
    }
}
