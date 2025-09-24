//
//  CollaborationRoomsList.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 8/20/25.
//

import SwiftUI

struct CollaborationRoomsList: View {
    @EnvironmentObject private var fileState: FileState
    
    @FetchRequest
    private var collaborationFiles: FetchedResults<CollaborationFile>
    @Binding var selections: Set<NSManagedObjectID>
    
    init(sortField: ExcalidrawFileSortField, selections: Binding<Set<NSManagedObjectID>>) {
        let sortDescriptors: [SortDescriptor<CollaborationFile>] = {
            switch sortField {
                case .updatedAt:
                    [
                        // SortDescriptor(\.visitedAt, order: .reverse),
                        SortDescriptor(\.updatedAt, order: .reverse),
                        SortDescriptor(\.createdAt, order: .reverse)
                    ]
                case .name:
                    [
                        SortDescriptor(\.name, order: .reverse),
                    ]
                case .rank:
                    [
                        SortDescriptor(\.rank, order: .forward),
                    ]
            }
        }()
        self._collaborationFiles = FetchRequest<CollaborationFile>(
            sortDescriptors: sortDescriptors,
            animation: .smooth
        )
        self._selections = selections
    }
    
    var body: some View {
        LazyVGrid(
            columns: [
                .init(
                    .adaptive(minimum: 240, maximum: 240 * 2 - 0.1),
                    spacing: 20
                )
            ],
            spacing: 20
        ) {
            content()
        }
    }
    
    
    @MainActor @ViewBuilder
    private func content() -> some View {
        ForEach(collaborationFiles) { room in
            CollaborationRoomItemView(
                room: room
            )
        }
    }
}


struct CollaborationRoomItemView: View {
    @EnvironmentObject private var fileState: FileState
    @EnvironmentObject private var collaborationState: CollaborationState
    
    var room: CollaborationFile

    var collaboratingState: ExcalidrawView.LoadingState? {
        fileState.collaboratingFilesState[room]
    }
    var stateIndicatorColor: Color {
        switch collaboratingState {
            case .none, .idle:
                return .gray
            case .loaded:
                return .green
            case .loading:
                return .yellow
            case .error:
                return .red
        }
    }
    
    var body: some View {
        FileHomeItemView(
            file: .collaborationFile(room)
        ) {
            VStack {
                HStack {
                    Text(room.name ?? String(localizable: .generalUntitled))
                        .lineLimit(1)
                        .font(.headline)
                    
                    Spacer()
                    
                    Circle()
                        .fill(stateIndicatorColor)
                        .shadow(color: stateIndicatorColor, radius: 2)
                        .frame(width: 6, height: 6)
                }
            }
        }
        .disabled(collaborationState.userCollaborationInfo.username.isEmpty)
    }
}
