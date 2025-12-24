//
//  CompactCollaborationHomeView.swift
//  ExcalidrawZ
//
//  Created by Chocoford on 12/19/25.
//

import SwiftUI
import CoreData

#if os(iOS)
struct CompactCollaborationHomeView: View {
    @Environment(\.alertToast) var alertToast

    @EnvironmentObject private var store: Store
    @EnvironmentObject private var fileState: FileState
    @EnvironmentObject private var collaborationState: CollaborationState

    @FetchRequest(sortDescriptors: [
        SortDescriptor(\.updatedAt, order: .reverse)
    ])
    private var collaborationFiles: FetchedResults<CollaborationFile>

    @FocusState private var isUsernameFieldFocused: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Header
                    header()

                    // Username field
                    usernameSection()

                    // Action buttons
                    actionButtons()

                    // Rooms list
                    if !collaborationFiles.isEmpty {
                        roomsList()
                    }
                }
                .padding()
            }
            .navigationTitle(.localizable(.collaborationHomeTitle))
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    SettingsViewButton()
                }
            }
        }
    }

    @ViewBuilder
    private func header() -> some View {
        VStack(spacing: 12) {
            Image(systemSymbol: .person3Fill)
                .font(.system(size: 60))
                .foregroundStyle(.blue.gradient)

            Text(.localizable(.collaborationHomeTitle))
                .font(.title2.bold())

            Text(.localizable(.collaborationHomeDescription))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical)
    }

    @ViewBuilder
    private func usernameSection() -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(.localizable(.collaborationHomeNameFieldLabel))
                .font(.headline)

            TextField(
                .localizable(.collaborationHomeNameFieldPlaceholder),
                text: $collaborationState.userCollaborationInfo.username
            )
            .textFieldStyle(.roundedBorder)
            .focused($isUsernameFieldFocused)
            .submitLabel(.done)

            if collaborationState.userCollaborationInfo.username.isEmpty && !isUsernameFieldFocused {
                Text(.localizable(.collaborationHomeNameFieldRequiredPopover))
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .padding(.horizontal)
    }

    @ViewBuilder
    private func actionButtons() -> some View {
        VStack(spacing: 12) {
            Button {
                if let limit = store.collaborationRoomLimits, collaborationFiles.count >= limit {
                    store.togglePaywall(reason: .roomLimit)
                } else {
                    collaborationState.isCreateRoomConfirmationDialogPresented.toggle()
                }
            } label: {
                Label(.localizable(.collaborationButtonCreateNewRoom), systemSymbol: .plusCircleFill)
                    .frame(maxWidth: .infinity)
            }
            .disabled(collaborationState.userCollaborationInfo.username.isEmpty)
            .modernButtonStyle(style: .glassProminent, size: .large, shape: .modern)

            Button {
                if let limit = store.collaborationRoomLimits, collaborationFiles.count >= limit {
                    store.togglePaywall(reason: .roomLimit)
                } else {
                    collaborationState.isJoinRoomSheetPresented.toggle()
                }
            } label: {
                Label(.localizable(.collaborationButtonJoinRoom), systemImage: "arrow.right.circle.fill")
                    .frame(maxWidth: .infinity)
            }
            .disabled(collaborationState.userCollaborationInfo.username.isEmpty)
            .modernButtonStyle(style: .glass, size: .large, shape: .modern)

        }
        .padding(.horizontal)
    }

    @ViewBuilder
    private func roomsList() -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Your Rooms")
                .font(.headline)
                .padding(.horizontal)

            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 16),
                    GridItem(.flexible(), spacing: 16)
                ],
                spacing: 16
            ) {
                ForEach(collaborationFiles) { room in
                    CollaborationRoomItemView(
                        room: room
                    )
                }
            }
            .padding(.horizontal)
        }
    }
}

#Preview {
    CompactCollaborationHomeView()
        .environmentObject(Store())
        .environmentObject(FileState())
        .environmentObject(CollaborationState())
}
#endif
