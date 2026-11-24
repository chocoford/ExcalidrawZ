//
//  LinkedStorageSidebarSection.swift
//  ExcalidrawZ
//

import SwiftUI
import SwiftyAlert
import CoreData

struct LinkedStorageSidebarSection: View {
    private enum Root: Identifiable {
        case local(LocalFolder)
        case cloud(CloudStorageLocation)

        var id: SidebarGroupScrollTarget {
            switch self {
                case .local(let folder): folder.sidebarGroupScrollTarget
                case .cloud(let location): .cloudStorageFolder(locationID: location.id, itemID: location.rootItemID)
            }
        }

        var orderID: String {
            switch self {
                case .local(let folder): "local:\(folder.objectID.uriRepresentation().absoluteString)"
                case .cloud(let location): "cloud:\(location.id.uuidString)"
            }
        }

        var dragItem: ItemDragState.DragItem {
            switch self {
                case .local(let folder): .localFolder(folder.objectID)
                case .cloud(let location): .cloudStorageLocation(location.id)
            }
        }
    }

    private enum SheetRoute: Identifiable {
        case serverCredentials(
            CloudStorageProviderDescriptor,
            reconnecting: CloudStorageLocation
        )

        var id: String {
            switch self {
                case .serverCredentials(let descriptor, let location):
                    "credentials:\(descriptor.id.rawValue):\(location.id.uuidString)"
            }
        }
    }

    @Environment(\.alertToast) private var alertToast
    @Environment(\.containerHorizontalSizeClass) private var containerHorizontalSizeClass
    @Environment(\.sidebarHoverSuppressed) private var hoverSuppressed
    @Environment(\.sidebarHoverAnimationsEnabled) private var hoverAnimationsEnabled
    @Environment(FileState.self) private var fileState
    @AppStorage("ShowLinkedStorageEmptyPlaceholder") private var showEmptyPlaceholder = true
    @AppStorage("LinkedStorageSidebarRootOrder") private var savedRootOrder = ""
    @State private var connections = CloudStorageConnectionStore.shared
    @State private var sheetRoute: SheetRoute?
    @State private var preparingProviderID: CloudStorageProviderID?
    @State private var isHovered = false

    private var showsHover: Bool { !hoverSuppressed && isHovered }

    private var locations: [CloudStorageLocation] {
        connections.locations.sorted { lhs, rhs in
            let lhsProvider = descriptor(for: lhs.providerID)?.displayName ?? ""
            let rhsProvider = descriptor(for: rhs.providerID)?.displayName ?? ""
            if lhsProvider != rhsProvider {
                return lhsProvider.localizedCaseInsensitiveCompare(rhsProvider) == .orderedAscending
            }
            return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
        }
    }

    var body: some View {
        LocalFoldersProvider { folders in
            let roots = orderedRoots(in: folders)
            let rootItems = Set(roots.map(\.dragItem))
            VStack(alignment: .leading, spacing: 0) {
                header

                if roots.isEmpty, showEmptyPlaceholder {
                    emptyPlaceholder
                        .background {
                            ZStack {
                                RoundedRectangle(cornerRadius: 20)
                                    .fill(.regularMaterial)
                                RoundedRectangle(cornerRadius: 20)
                                    .stroke(.secondary, lineWidth: 0.5)
                            }
                        }
                        .padding(.vertical, 10)
                        .transition(.scale(scale: 0, anchor: .topTrailing).combined(with: .opacity))
                } else {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(roots) { root in
                            Section {
                                rootRow(root, folders: folders, rootItems: rootItems)
                            }
                        }
                    }
                    .animation(.smooth(duration: 0.2), value: savedRootOrder)
                    .modifier(LocalFolderSidebarExpansionModifier())
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .trackSidebarHover($isHovered)
            .animation(.smooth, value: showEmptyPlaceholder)
        }
        .sheet(item: $sheetRoute) { route in
            switch route {
                case .serverCredentials(let descriptor, let location):
                    CloudStorageServerConnectionSheet(
                        providerName: descriptor.displayName,
                        connectedAccounts: []
                    ) { credentials in
                        try await reconnect(
                            location,
                            using: .serverCredentials(credentials)
                        )
                    }
            }
        }
    }

    private func defaultRoots(in folders: FetchedResults<LocalFolder>) -> [Root] {
        folders.map(Root.local) + locations.map(Root.cloud)
    }

    private func orderedRoots(in folders: FetchedResults<LocalFolder>) -> [Root] {
        let roots = defaultRoots(in: folders)
        let order = LinkedStorageRootOrder(savedOrder: savedRootOrder, defaultIDs: roots.map(\.orderID))
        let rootsByID = Dictionary(uniqueKeysWithValues: roots.map { ($0.orderID, $0) })
        return order.ids.compactMap { rootsByID[$0] }
    }

    @ViewBuilder
    private func rootRow(_ root: Root, folders: FetchedResults<LocalFolder>, rootItems: Set<ItemDragState.DragItem>) -> some View {
        let reorder = LinkedStorageRootReorderAction(item: root.dragItem, contains: { rootItems.contains($0) }) { source, edge in
            let roots = defaultRoots(in: folders)
            guard let sourceRoot = roots.first(where: { $0.dragItem == source }) else { return }
            var order = LinkedStorageRootOrder(savedOrder: savedRootOrder, defaultIDs: roots.map(\.orderID))
            if order.move(sourceRoot.orderID, relativeTo: root.orderID, edge: edge) {
                savedRootOrder = order.savedOrder
            }
        }

        switch root {
            case .local(let folder):
                LocalFoldersView(folder: folder, sortField: fileState.sortField, reorder: reorder) {
                    fileState.selectNeighborAfterRemovingLocalFolder(folder, from: folders)
                }
            case .cloud(let location):
                CloudStorageSidebarLocationRow(location: location, connections: connections, reorder: reorder) {
                    CloudStorageProviderIcon(
                        providerID: location.providerID,
                        size: 18,
                        accountDisplayName: connections.account(for: location)?.displayName
                    )
                } onReconnect: {
                    reconnect(location)
                }
        }
    }

    private var header: some View {
        HStack {
            Text(.localizable(.linkedStorageTitle))
                .foregroundStyle(.secondary)

            Spacer()

            LinkedStorageAddMenu { isAdding in
                if isAdding || preparingProviderID != nil {
                    ProgressView()
                        .controlSize(.mini)
                } else {
                    SidebarSectionAddIcon(
                        accessibilityLabel: Text(.localizable(.linkedStorageAddStorage))
                    )
                }
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            .disabled(preparingProviderID != nil)
            .opacity(showsHover || isLoading ? 1 : 0.4)
            .animation(
                hoverAnimationsEnabled && !hoverSuppressed ? .smooth : nil,
                value: showsHover
            )
#if os(macOS)
            .controlSize(.large)
            .padding(.trailing, 2)
#endif
        }
        .frame(maxWidth: .infinity)
        .font(.callout.bold())
    }

    private var isLoading: Bool {
        preparingProviderID != nil || !connections.connectingProviderIDs.isEmpty
    }

    private var emptyPlaceholder: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                LinkedStorageLocalFolderIcon(size: 28)
                    .frame(width: 32, height: 32)

                ForEach(Self.supportedProviderIDs, id: \.self) { providerID in
                    CloudStorageProviderIcon(providerID: providerID, size: 28)
                        .frame(width: 32, height: 32)
                }
            }

            Text(.localizable(.linkedStorageEmptyDescription))
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            VStack(spacing: 6) {
                LinkedStorageAddMenu { isAdding in
                    if isAdding {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Label(
                            String(localizable: .linkedStorageAddStorage),
                            systemImage: "link.badge.plus"
                        )
                    }
                }
                .font(.footnote)
                .modernButtonStyle(style: .glassProminent, shape: .modern)

                if containerHorizontalSizeClass == .compact {
                    Button {
                        showEmptyPlaceholder = false
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "xmark")
                            Text(localizable: .generalButtonClose)
                        }
                    }
                    .font(.footnote)
                    .modernButtonStyle(style: .glass, shape: .modern)
                }
            }
        }
        .padding(.vertical, 24)
        .frame(maxWidth: .infinity)
        .overlay(alignment: .topLeading) {
            if containerHorizontalSizeClass != .compact {
                Button {
                    showEmptyPlaceholder = false
                } label: {
                    Image(systemName: "xmark")
                        .foregroundStyle(.secondary)
                }
                .modernButtonStyle(style: .borderless)
                .padding()
            }
        }
    }

    private func reconnect(_ location: CloudStorageLocation) {
        guard let descriptor = descriptor(for: location.providerID) else { return }
        if descriptor.connectionMethod == .serverCredentials {
            sheetRoute = .serverCredentials(descriptor, reconnecting: location)
            return
        }

        guard preparingProviderID == nil else { return }
        preparingProviderID = location.providerID
        Task {
            defer { preparingProviderID = nil }
            do {
                _ = try await connections.ensureAccess(to: location)
                await CloudStorageSyncService.shared.prioritizeDocuments(
                    in: location,
                    parentID: location.rootItemID,
                    connections: connections
                )
            } catch CloudStorageError.authorizationCancelled {
                return
            } catch {
                alertToast(error)
            }
        }
    }

    private func reconnect(
        _ location: CloudStorageLocation,
        using connectionInput: CloudStorageConnectionInput
    ) async throws {
        let account = try await connections.connect(
            to: location.providerID,
            using: connectionInput
        )
        guard account.id == location.accountID else {
            throw CloudStorageError.invalidProviderResponse(
                "These credentials belong to a different WebDAV account or server."
            )
        }
        connections.clearAuthenticationRequirement(for: location)
        CloudStorageDocumentStore.shared.invalidateSession(for: location.id)
        sheetRoute = nil
        await CloudStorageSyncService.shared.prioritizeDocuments(
            in: location,
            parentID: location.rootItemID,
            connections: connections
        )
    }

    private func descriptor(
        for providerID: CloudStorageProviderID
    ) -> CloudStorageProviderDescriptor? {
        connections.providerDescriptors.first { $0.id == providerID }
    }

    private static let supportedProviderIDs: [CloudStorageProviderID] = [
        .microsoftOneDrive,
        .dropbox,
        .webDAV,
    ]

}
