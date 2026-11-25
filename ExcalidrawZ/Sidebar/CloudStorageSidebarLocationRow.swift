//
//  CloudStorageSidebarLocationRow.swift
//  ExcalidrawZ
//

import SwiftUI
import UniformTypeIdentifiers

struct CloudStorageSidebarLocationRow<Icon: View>: View {
    @Environment(FileState.self) private var fileState
    @Bindable private var connectivity = CloudStorageConnectivityMonitor.shared

    let location: CloudStorageLocation
    @Bindable var connections: CloudStorageConnectionStore
    let icon: Icon
    let reorder: SidebarRowReorderAction
    let onReconnect: () -> Void

    @State private var browser: CloudStorageSidebarBrowserModel
    @State private var isExpanded = false

    init(
        location: CloudStorageLocation,
        connections: CloudStorageConnectionStore,
        reorder: SidebarRowReorderAction,
        @ViewBuilder icon: () -> Icon,
        onReconnect: @escaping () -> Void
    ) {
        self.location = location
        self.connections = connections
        self.icon = icon()
        self.reorder = reorder
        self.onReconnect = onReconnect
        self._browser = State(
            initialValue: CloudStorageSidebarBrowserModel(location: location)
        )
    }

    var body: some View {
        SelectableDisclosureGroup(
            isSelected: selectionBinding,
            isExpanded: $isExpanded
        ) {
            CloudStorageSidebarFolderContents(
                folderID: location.rootItemID,
                browser: browser,
                connections: connections
            )
        } label: {
            HStack(spacing: 6) {
                icon
                    .frame(width: 18, height: 16)
                Text(location.displayName)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 4)
                if isConnecting {
                    ProgressView()
                        .controlSize(.mini)
                        .frame(width: 12, height: 12)
                } else if connections.requiresAuthentication(for: location) {
                    Button(action: onReconnect) {
                        Image(systemName: "exclamationmark.circle.fill")
                            .imageScale(.small)
                            .foregroundStyle(.orange)
                            .frame(width: 12, height: 12)
                    }
                    .buttonStyle(.borderless)
                    .help(.localizable(.cloudStorageSignInReconnectFormat(location.displayName)))
                } else if connectivity.status == .unavailable {
                    Image(systemName: "wifi.slash")
                        .imageScale(.small)
                        .foregroundStyle(.secondary)
                        .frame(width: 12, height: 12)
                        .help(
                            String(localizable: .cloudStorageStatusWaitingForConnection)
                        )
                } else if isLoadingMetadata {
                    ProgressView()
                        .controlSize(.mini)
                        .frame(width: 12, height: 12)
                } else {
                    CloudStorageFolderSyncIndicator(state: folderSyncState)
                }
            }
            .contentShape(Rectangle())
            .modifier(CloudStorageLocationActionsModifier(location: location))
            .id(scrollTarget)
        }
        .extraLabelStyle { content in
            content
                .modifier(CloudStorageLocationDragModifier(locationID: location.id))
                .modifier(SidebarRowReorderModifier(action: reorder))
        }
        .disclosureGroupIndicatorVisibility(.visible)
        .expandForSidebarFileReveal(scrollTarget, isExpanded: $isExpanded, selectedFolderID: selectedFolderID)
    }

    private var scrollTarget: SidebarGroupScrollTarget {
        .cloudStorageFolder(locationID: location.id, itemID: location.rootItemID)
    }

    private var selectedFolderID: String? {
        guard fileState.currentActiveFile == nil,
              case .cloudStorageFolder(let folder) = fileState.currentActiveGroup,
              folder.location.id == location.id else { return nil }
        return folder.id
    }

    private var selectionBinding: Binding<Bool> {
        Binding(
            get: {
                fileState.currentActiveGroup == .cloudStorageFolder(.root(of: location))
                    && fileState.currentActiveFile == nil
            },
            set: { selected in
                guard selected else { return }
                DispatchQueue.main.async {
                    fileState.setActiveGroupIfNeeded(.cloudStorageFolder(.root(of: location)))
                    fileState.setActiveFile(nil)
                    Task { @MainActor in
                        await CloudStorageSyncService.shared
                            .prioritizeDocumentsAfterUserEntry(
                                in: location,
                                parentID: location.rootItemID,
                                connections: connections
                            )
                    }
                }
            }
        )
    }

    private var isLoadingMetadata: Bool {
        browser.isRefreshing
            && browser.items(
                in: location.rootItemID,
                sortedBy: fileState.sortField
            ) == nil
    }

    private var isConnecting: Bool {
        connections.connectingProviderIDs.contains(location.providerID)
    }

    private var folderSyncState: CloudStorageFolderSyncState {
        browser.folderSyncState(in: location.rootItemID)
    }

}

private struct CloudStorageSidebarFolderContents: View {
    @Environment(FileState.self) private var fileState
    @Bindable private var connectivity = CloudStorageConnectivityMonitor.shared

    let folderID: CloudStorageItemID
    @Bindable var browser: CloudStorageSidebarBrowserModel
    @Bindable var connections: CloudStorageConnectionStore

    var body: some View {
        let items = items
        VStack(alignment: .leading, spacing: 0) {
            if items == nil {
                if connectivity.status == .unavailable {
                    statusRow {
                        Image(systemName: "wifi.slash")
                        Text(
                            String(localizable: .cloudStorageStatusOffline)
                        )
                    }
                } else if let errorMessage = browser.errorMessage,
                   !browser.isRefreshing {
                    statusRow {
                        Image(systemName: "exclamationmark.triangle")
                        Text(errorMessage)
                            .lineLimit(1)
                        Spacer(minLength: 4)
                        Button {
                            Task {
                                await browser.refresh(connections: connections)
                            }
                        } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                        .buttonStyle(.borderless)
                    }
                } else {
                    statusRow {
                        ProgressView()
                            .controlSize(.mini)
                        Text(localizable: .generalLoading)
                    }
                }
            } else if let items {
                if items.isEmpty {
                    statusRow {
                        Text(.localizable(.cloudStorageNoExcalidrawFiles))
                    }
                } else {
                    ForEach(items) { item in
                        if item.kind == .folder {
                            CloudStorageSidebarFolderRow(
                                folder: item,
                                browser: browser,
                                connections: connections
                            )
                        } else {
                            CloudStorageSidebarFileRow(
                                item: item,
                                browser: browser
                            )
                        }
                    }
                }
            }
        }
        .reportSidebarFileRevealContents(
            of: .cloudStorageFolder(locationID: browser.location.id, itemID: folderID),
            available: items != nil,
            fileAvailable: containsActiveFile(in: items)
        ) { target in
            guard case .cloudStorageFolder(let locationID, let itemID) = target,
                  locationID == browser.location.id else { return false }
            return items?.contains { $0.kind == .folder && $0.id == itemID } == true
        }
        .task(id: folderID) {
            await CloudStorageSyncService.shared.prioritizeDocuments(
                in: browser.location,
                parentID: folderID,
                connections: connections
            )
        }
    }

    private var items: [CloudStorageItem]? {
        browser.items(in: folderID, sortedBy: fileState.sortField)
    }

    private func containsActiveFile(in items: [CloudStorageItem]?) -> Bool {
        guard case .cloudStorageFile(let file) = fileState.currentActiveFile,
              file.locationID == browser.location.id else { return false }
        return items?.contains { $0.kind == .file && $0.id == file.itemID } == true
    }

    private func statusRow<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(spacing: 6) {
            content()
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.leading, 22)
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct CloudStorageSidebarFolderRow: View {
    @Environment(FileState.self) private var fileState

    let folder: CloudStorageItem
    @Bindable var browser: CloudStorageSidebarBrowserModel
    @Bindable var connections: CloudStorageConnectionStore

    @State private var isExpanded = false

    var body: some View {
        SelectableDisclosureGroup(
            isSelected: selectionBinding,
            isExpanded: $isExpanded
        ) {
            CloudStorageSidebarFolderContents(
                folderID: folder.id,
                browser: browser,
                connections: connections
            )
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "folder.fill")
                    .font(.system(size: 15))
                    .foregroundStyle(.blue)
                    .frame(width: 18, height: 16)
                Text(folder.name)
                Spacer(minLength: 4)
                CloudStorageFolderSyncIndicator(
                    state: browser.folderSyncState(in: folder.id)
                )
            }
            .lineLimit(1)
            .truncationMode(.middle)
            .contentShape(Rectangle())
            .modifier(CloudStorageFolderActionsModifier(folder: reference))
            .id(scrollTarget)
        }
        .disclosureGroupIndicatorVisibility(.visible)
        .expandForSidebarFileReveal(scrollTarget, isExpanded: $isExpanded, selectedFolderID: selectedFolderID)
    }

    private var scrollTarget: SidebarGroupScrollTarget {
        .cloudStorageFolder(locationID: browser.location.id, itemID: folder.id)
    }

    private var selectedFolderID: String? {
        guard fileState.currentActiveFile == nil,
              case .cloudStorageFolder(let selectedFolder) = fileState.currentActiveGroup,
              selectedFolder.location.id == browser.location.id,
              browser.folderIDs(inPathTo: selectedFolder).contains(folder.id) else { return nil }
        return selectedFolder.id
    }

    private var reference: CloudStorageFolderReference {
        CloudStorageFolderReference(location: browser.location, item: folder)
    }

    private var selectionBinding: Binding<Bool> {
        Binding(
            get: {
                fileState.currentActiveGroup == .cloudStorageFolder(reference)
                    && fileState.currentActiveFile == nil
            },
            set: { selected in
                guard selected else { return }
                DispatchQueue.main.async {
                    fileState.setActiveGroupIfNeeded(.cloudStorageFolder(reference))
                    fileState.setActiveFile(nil)
                    Task { @MainActor in
                        await CloudStorageSyncService.shared
                            .prioritizeDocumentsAfterUserEntry(
                                in: browser.location,
                                parentID: folder.id,
                                connections: connections
                            )
                    }
                }
            }
        )
    }

}

private struct CloudStorageSidebarFileRow: View {
    @Environment(FileState.self) private var fileState

    let item: CloudStorageItem
    @Bindable var browser: CloudStorageSidebarBrowserModel

    var body: some View {
        let isActive = fileState.currentActiveFile == .cloudStorageFile(reference)
        let scrollTarget = SidebarActiveFileScrollTarget.cloudStorageFile(reference.id)
        FileRowButton(
            isSelected: isActive,
            isMultiSelected: false,
            onTap: open
        ) {
            FileRowLabel(
                name: displayName,
                fileType: reference.fileType,
                updatedAt: item.modifiedAt ?? .distantPast
            ) {
                CloudStorageDocumentSyncIndicator(
                    reference: reference,
                    presentation: .sidebar
                )
            }
        }
        .modifier(CloudStorageFileActionsModifier(reference: reference))
        .id(scrollTarget)
    }

    private var reference: CloudStorageDocumentReference {
        CloudStorageDocumentReference(
            locationID: browser.location.id,
            providerID: browser.location.providerID,
            accountID: browser.location.accountID,
            itemID: item.id,
            lastKnownName: item.name,
            lastKnownModifiedAt: item.modifiedAt
        )
    }

    private func open() {
        if let parent = CloudStorageDocumentStore.shared.bestKnownParentFolder(for: reference) {
            fileState.setActiveGroupIfNeeded(.cloudStorageFolder(parent))
        }
        fileState.setActiveFile(.cloudStorageFile(reference))
    }

    private var displayName: String {
        let name = item.name as NSString
        let extensionName = name.pathExtension.lowercased()
        let withoutLastExtension = name.deletingPathExtension as NSString

        if ["png", "svg"].contains(extensionName),
           withoutLastExtension.pathExtension.lowercased() == "excalidraw" {
            return withoutLastExtension.deletingPathExtension
        }
        return withoutLastExtension as String
    }
}

private struct CloudStorageFolderSyncIndicator: View {
    @Bindable private var connectivity = CloudStorageConnectivityMonitor.shared

    let state: CloudStorageFolderSyncState

    @ViewBuilder
    var body: some View {
        switch state {
            case .synchronizing:
                ProgressView()
                    .controlSize(.mini)
                    .frame(width: 12, height: 12)
            case .queued(let direction):
                Image(systemName: connectivity.status == .unavailable
                      ? "wifi.slash"
                      : direction.symbolName)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(width: 12, height: 12)
            case .idle:
                EmptyView()
        }
    }
}

private extension CloudStoragePendingSyncDirection {
    var symbolName: String {
        switch self {
            case .upload:
                "icloud.and.arrow.up"
            case .download:
                "icloud.and.arrow.down"
        }
    }
}

private extension CloudStorageDocumentReference {
    var fileType: UTType {
        let pathExtension = (lastKnownName as NSString).pathExtension.lowercased()
        return pathExtension == "svg"
            ? .excalidrawSVG
            : pathExtension == "png"
            ? .excalidrawPNG
            : .excalidrawFile
    }
}
