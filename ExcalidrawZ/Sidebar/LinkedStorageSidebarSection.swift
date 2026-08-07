//
//  LinkedStorageSidebarSection.swift
//  ExcalidrawZ
//

import SwiftUI
#if os(macOS)
import AppKit
#endif

struct LinkedStorageSidebarSection: View {
    private enum SheetRoute: Identifiable {
        case serverCredentials(
            CloudStorageProviderDescriptor,
            reconnecting: CloudStorageLocation?
        )
        case folderPicker(CloudStorageFolderPickerContext)

        var id: String {
            switch self {
                case .serverCredentials(let descriptor, let location):
                    "credentials:\(descriptor.id.rawValue):\(location?.id.uuidString ?? "new")"
                case .folderPicker(let context):
                    "folder-picker:\(context.id.uuidString)"
            }
        }
    }

    @Environment(\.alertToast) private var alertToast
    @Environment(\.containerHorizontalSizeClass) private var containerHorizontalSizeClass
    @AppStorage("ShowLinkedStorageEmptyPlaceholder") private var showEmptyPlaceholder = true
    @StateObject private var connections = CloudStorageConnectionStore.shared
    @State private var sheetRoute: SheetRoute?
    @State private var preparingProviderID: CloudStorageProviderID?
    @State private var isImportLocalFolderDialogPresented = false
    @State private var isHovered = false

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
            VStack(alignment: .leading, spacing: 0) {
                header

                LocalFoldersListContent(
                    folders: folders,
                    showFiles: true,
                    showsEmptyPlaceholder: false
                )

                ForEach(locations) { location in
                    CloudStorageSidebarLocationRow(
                        location: location,
                        connections: connections
                    ) {
                        CloudStorageProviderIcon(
                            providerID: location.providerID,
                            size: 18,
                            accountDisplayName: connections.account(for: location)?.displayName
                        )
                    } onReconnect: {
                        reconnect(location)
                    }
                }

                if folders.isEmpty, locations.isEmpty, showEmptyPlaceholder {
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
                }
            }
            .contentShape(Rectangle())
            .onHover { isHovered = $0 }
            .animation(.smooth, value: showEmptyPlaceholder)
        }
        .sheet(item: $sheetRoute) { route in
            switch route {
                case .serverCredentials(let descriptor, let location):
                    CloudStorageServerConnectionSheet(
                        providerName: descriptor.displayName,
                        connectedAccounts: location == nil
                            ? connections.accounts(for: descriptor.id)
                            : [],
                        onSelectAccount: { account in
                            try await preparePicker(
                                providerID: descriptor.id,
                                account: account
                            )
                        }
                    ) { credentials in
                        if let location {
                            try await reconnect(
                                location,
                                using: .serverCredentials(credentials)
                            )
                        } else {
                            try await selectLocation(
                                with: descriptor.id,
                                account: nil,
                                connectionInput: .serverCredentials(credentials)
                            )
                        }
                    }
                case .folderPicker(let context):
                    CloudStorageFolderPicker(context: context) { folder in
                        connections.saveLocation(
                            providerID: context.providerID,
                            account: context.account,
                            folder: folder
                        )
                    }
            }
        }
    }

    private var header: some View {
        HStack {
            Text("Linked Storage")
                .foregroundStyle(.secondary)

            Spacer()

            ZStack {
                if isLoading {
                    ProgressView()
                        .controlSize(.mini)
                } else {
                    storageMenu {
                        Label("Add Storage", systemImage: "plus.circle.fill")
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                }
            }
            .opacity(isHovered || isLoading ? 1 : 0.4)
#if os(macOS)
            .controlSize(.large)
            .padding(.trailing, 2)
#endif
        }
        .font(.callout.bold())
#if os(iOS)
        .tint(.secondary)
#endif
        .animation(.smooth, value: isHovered)
    }

    private var isLoading: Bool {
        preparingProviderID != nil || !connections.connectingProviderIDs.isEmpty
    }

    private var emptyPlaceholder: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                localFolderIcon(size: 28)
                    .frame(width: 32, height: 32)

                ForEach(Self.supportedProviderIDs, id: \.self) { providerID in
                    CloudStorageProviderIcon(providerID: providerID, size: 28)
                        .frame(width: 32, height: 32)
                }
            }

            Text("Link a local folder or cloud storage to browse drawings from one place.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            VStack(spacing: 6) {
                storageMenu {
                    Label("Add Storage", systemImage: "link.badge.plus")
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

    private func addLocation(to providerID: CloudStorageProviderID) {
        guard preparingProviderID == nil else { return }
        if let descriptor = descriptor(for: providerID),
           descriptor.connectionMethod == .serverCredentials {
            sheetRoute = .serverCredentials(descriptor, reconnecting: nil)
            return
        }

        preparingProviderID = providerID
        Task {
            defer { preparingProviderID = nil }
            do {
                try await selectLocation(
                    with: providerID,
                    account: connections.accounts(for: providerID).first,
                    connectionInput: nil
                )
            } catch CloudStorageError.authorizationCancelled {
                return
            } catch {
                alertToast(error)
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

    private func selectLocation(
        with providerID: CloudStorageProviderID,
        account: CloudStorageAccount?,
        connectionInput: CloudStorageConnectionInput?
    ) async throws {
        let selection = try await connections.selectLocation(
            with: providerID,
            account: account,
            connectionInput: connectionInput
        )
        switch selection {
            case .browse(let account):
                try await preparePicker(providerID: providerID, account: account)
            case .selected(let account, let folder):
                connections.saveLocation(
                    providerID: providerID,
                    account: account,
                    folder: folder
                )
                sheetRoute = nil
        }
    }

    private func preparePicker(
        providerID: CloudStorageProviderID,
        account: CloudStorageAccount
    ) async throws {
        let session = try await connections.makeSession(
            providerID: providerID,
            account: account
        )
        sheetRoute = .folderPicker(
            CloudStorageFolderPickerContext(
                providerID: providerID,
                providerName: descriptor(for: providerID)?.displayName ?? "Cloud Storage",
                account: account,
                session: session
            )
        )
    }

    @ViewBuilder
    private func storageMenu<MenuLabel: View>(
        @ViewBuilder label: () -> MenuLabel
    ) -> some View {
        Menu {
            Button {
                isImportLocalFolderDialogPresented = true
            } label: {
                HStack {
                    localFolderIcon(size: 16)
                    Text("Link Local Folder")
                }
            }

            Section("Or Cloud Storage") {
                ForEach(connections.providerDescriptors, id: \.id) { descriptor in
                    Button {
                        addLocation(to: descriptor.id)
                    } label: {
                        HStack {
                            CloudStorageProviderIcon(providerID: descriptor.id, size: 16)
                            Text(descriptor.displayName)
                        }
                    }
                    .badge(menuBadge(for: descriptor))
                }
            }

        } label: {
            label()
        }
        .menuIndicator(.hidden)
        .fixedSize()
        .modifier(ImportLocalFolderModifier(isPresented: $isImportLocalFolderDialogPresented))
    }

    private func menuBadge(
        for descriptor: CloudStorageProviderDescriptor
    ) -> Text? {
        if descriptor.id == .webDAV {
            return Text("Beta")
                .foregroundColor(.yellow)
                .bold()
        }
        if !connections.accounts(for: descriptor.id).isEmpty {
            return Text("Connected")
                .foregroundColor(.green)
                .bold()
        }
        return nil
    }

    private func descriptor(
        for providerID: CloudStorageProviderID
    ) -> CloudStorageProviderDescriptor? {
        connections.providerDescriptors.first { $0.id == providerID }
    }

    private static let supportedProviderIDs: [CloudStorageProviderID] = [
        .microsoftOneDrive,
        .googleDrive,
        .dropbox,
        .webDAV,
    ]

    @ViewBuilder
    private func localFolderIcon(size: CGFloat) -> some View {
#if os(macOS)
        if let finderURL = NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: "com.apple.finder"
        ) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: finderURL.path))
                .resizable()
                .scaledToFit()
                .frame(width: size, height: size)
        } else {
            Image(systemName: "folder.fill")
                .font(.system(size: size, weight: .medium))
                .foregroundStyle(.secondary)
        }
#else
        Image(systemName: "folder.fill")
            .font(.system(size: size, weight: .medium))
            .foregroundStyle(.secondary)
#endif
    }

}
