//
//  FileHomeView.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 8/3/25.
//

import SwiftUI
import ChocofordUI
import SmoothGradient

struct FileHomeView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.alertToast) private var alertToast

    @EnvironmentObject var fileState: FileState

    var group: Group
    var parentGroups: [Group]
    
    @FetchRequest
    private var files: FetchedResults<File>
    @FetchRequest
    private var childGroups: FetchedResults<Group>
    
    init(group: Group) {
        self.group = group
        self.parentGroups = {
            var parents: [Group] = []
            var currentGroup: Group? = group
            while let parent = currentGroup?.parent {
                parents.append(parent)
                currentGroup = parent
            }
            return parents.reversed()
        }()
        self._files = FetchRequest<File>(
            sortDescriptors: [
                NSSortDescriptor(keyPath: \File.createdAt, ascending: false),
                NSSortDescriptor(keyPath: \File.updatedAt, ascending: false),
                NSSortDescriptor(keyPath: \File.visitedAt, ascending: false),
            ],
            predicate: group.groupType == .trash
            ? NSPredicate(format: "inTrash == true")
            : NSPredicate(format: "inTrash == false AND group == %@", group),
            animation: .default
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
    
    @State private var isCreateGroupDialogPresented: Bool = false
    
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
    
    let fileItemWidth: CGFloat = 240
    let folderItemWidth: CGFloat = 220
    
    @MainActor @ViewBuilder
    private func content() -> some View {
        ScrollView {
            VStack(spacing: 0) {
                VStack(spacing: 30) {
                    // Header
                    VStack(spacing: 0) {
                        HStack(spacing: 2) {
                            ForEach(parentGroups) { group in
                                Button {
                                    fileState.currentActiveFile = nil
                                    fileState.currentActiveGroup = .group(group)
                                } label: {
                                    Text(group.name ?? String(localizable: .generalUntitled))
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                                .buttonStyle(.text(size: .small))
                                .hoverCursor(.pointingHand)

                                if group != parentGroups.last {
                                    Image(systemSymbol: .chevronRight)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                        }
                        .font(.caption)
                        
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
                        .padding(.horizontal, 10)
                    }
                    .padding(.horizontal, 20)
                    
                    SwiftUI.Group {
                        // Quick Actions
                        HStack(spacing: 10) {
                            NewFileButton(openWithDelay: true)
                                .hoverCursor(.pointingHand)
                            
                            Button {
                                isCreateGroupDialogPresented.toggle()
                            } label: {
                                Label("New Group", systemSymbol: .folderBadgePlus)
                            }
                            .hoverCursor(.pointingHand)

                            Spacer()
                        }
                        .controlSize(.large)
                        .modifier(CreateGroupModifier(
                            isPresented: $isCreateGroupDialogPresented
                        ))
                        .onHover { isHovered in
                            if isHovered {
                                NSCursor.pointingHand.set()
                            } else {
                                NSCursor.arrow.set()
                            }
                        }
                        // Groups
                        LazyVGrid(
                            columns: [.init(.adaptive(minimum: folderItemWidth, maximum: folderItemWidth * 2 - 0.1), spacing: 20)],
                            spacing: 20
                        ) {
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
                        LazyVGrid(
                            columns: [.init(.adaptive(minimum: fileItemWidth, maximum: fileItemWidth * 2 - 0.1), spacing: 20)],
                            spacing: 20
                        ) {
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
                    .padding(.horizontal, 30)
                }
                .padding(.top, parentGroups.isEmpty ? 36 : 15)
                .padding(.bottom, 30)
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
                    .overlay(alignment: .top) {
                        if files.isEmpty {
                            LazyVGrid(
                                columns: [.init(.adaptive(minimum: fileItemWidth, maximum: fileItemWidth * 2 - 0.1), spacing: 20)],
                                spacing: 20
                            ) {
                                ForEach(0..<30) { _ in
                                    FileHomeItemView.placeholder()
                                }
                            }
                            .padding(.horizontal, 30)
                            
                        }
                    }
                    .mask {
                        if files.isEmpty {
                            if #available(macOS 14.0, iOS 16.0, *) {
                                Rectangle()
                                    .fill(
                                        SmoothLinearGradient(
                                            from: Color.white,
                                            to: Color.white.opacity(0.0),
                                            startPoint: .top,
                                            endPoint: .bottom
                                        )
                                    )
                            } else {
                                Rectangle()
                                    .fill(
                                        LinearGradient(
                                            colors: [.white, .white.opacity(0.0)],
                                            startPoint: .top,
                                            endPoint: .bottom
                                        )
                                    )
                            }
                        } else {
                            Color.white
                        }
                    }
                    .overlay {
                        if files.isEmpty {
                            if #available(macOS 14.0, iOS 16.0, *) {
                                Text("No files...")
                                    .foregroundStyle(.placeholder)
                            } else {
                                Text("No files...")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
            }
        }
    }
    
    
}


struct EmptyFilesPlaceholderModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
    }
}
