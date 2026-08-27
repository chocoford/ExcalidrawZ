//
//  LinkedStorageAddMenu.swift
//  ExcalidrawZ
//

import SwiftUI
#if os(macOS)
import AppKit
#endif

/// Shared entry point for linking local folders and provider-backed storage.
/// It owns the complete connection flow so Sidebar and compact Browse stay aligned.
struct LinkedStorageAddMenu<AdditionalContent: View, Label: View>: View {
    private enum SheetRoute: Identifiable {
        case serverCredentials(CloudStorageProviderDescriptor)
        case folderPicker(CloudStorageFolderPickerContext)

        var id: String {
            switch self {
                case .serverCredentials(let descriptor):
                    "credentials:\(descriptor.id.rawValue)"
                case .folderPicker(let context):
                    "folder-picker:\(context.id.uuidString)"
            }
        }
    }

    @Environment(\.alertToast) private var alertToast
    @StateObject private var connections = CloudStorageConnectionStore.shared
    @State private var sheetRoute: SheetRoute?
    @State private var preparingProviderID: CloudStorageProviderID?
    @State private var isImportLocalFolderDialogPresented = false

    private let additionalContent: () -> AdditionalContent
    private let label: (Bool) -> Label

    init(
        @ViewBuilder additionalContent: @escaping () -> AdditionalContent,
        @ViewBuilder label: @escaping (Bool) -> Label
    ) {
        self.additionalContent = additionalContent
        self.label = label
    }

    var body: some View {
        ZStack {
            if isLoading {
                label(true)
                    .transition(.opacity)
            } else {
                addStorageMenu
                    .transition(.opacity)
            }
        }
        .animation(.smooth, value: isLoading)
        .modifier(
            ImportLocalFolderModifier(
                isPresented: $isImportLocalFolderDialogPresented
            )
        )
        .sheet(item: $sheetRoute) { route in
            switch route {
                case .serverCredentials(let descriptor):
                    CloudStorageServerConnectionSheet(
                        providerName: descriptor.displayName,
                        connectedAccounts: connections.accounts(for: descriptor.id),
                        onSelectAccount: { account in
                            try await preparePicker(
                                providerID: descriptor.id,
                                account: account
                            )
                        }
                    ) { credentials in
                        try await selectLocation(
                            with: descriptor.id,
                            account: nil,
                            connectionInput: .serverCredentials(credentials)
                        )
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

    private var addStorageMenu: some View {
        Menu {
            additionalContent()

            Button {
                isImportLocalFolderDialogPresented = true
            } label: {
                HStack {
                    LinkedStorageLocalFolderIcon(size: 16)
                    Text(String(
                        localized: "linkedStorageLinkLocalFolder",
                        defaultValue: "Link Local Folder"
                    ))
                }
            }

            Section(String(
                localized: "linkedStorageCloudStorageSection",
                defaultValue: "Or Cloud Storage"
            )) {
                ForEach(availableProviderDescriptors, id: \.id) { descriptor in
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
            label(false)
        }
        .menuIndicator(.hidden)
    }

    private var isLoading: Bool {
        preparingProviderID != nil || !connections.connectingProviderIDs.isEmpty
    }

    private var availableProviderDescriptors: [CloudStorageProviderDescriptor] {
        connections.providerDescriptors.filter { $0.id != .googleDrive }
    }

    private func addLocation(to providerID: CloudStorageProviderID) {
        guard preparingProviderID == nil else { return }
        if let descriptor = descriptor(for: providerID),
           descriptor.connectionMethod == .serverCredentials {
            sheetRoute = .serverCredentials(descriptor)
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
                providerName: descriptor(for: providerID)?.displayName ?? String(
                    localized: "linkedStorageCloudStorageFallbackName",
                    defaultValue: "Cloud Storage"
                ),
                account: account,
                session: session
            )
        )
    }

    private func menuBadge(
        for descriptor: CloudStorageProviderDescriptor
    ) -> Text? {
        if descriptor.id == .webDAV {
            return Text(String(
                localized: "generalBadgeBeta",
                defaultValue: "Beta"
            ))
                .foregroundColor(.yellow)
                .bold()
        }
        if !connections.accounts(for: descriptor.id).isEmpty {
            return Text(String(
                localized: "cloudStorageConnectedBadge",
                defaultValue: "Connected"
            ))
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

}

struct LinkedStorageLocalFolderIcon: View {
    let size: CGFloat

    @ViewBuilder
    var body: some View {
#if os(macOS)
        if let finderURL = NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: "com.apple.finder"
        ) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: finderURL.path))
                .resizable()
                .scaledToFit()
                .frame(width: size, height: size)
        } else {
            fallbackIcon
        }
#else
        fallbackIcon
#endif
    }

    private var fallbackIcon: some View {
        Image(systemName: "folder.fill")
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .foregroundStyle(.secondary)
    }
}

extension LinkedStorageAddMenu where AdditionalContent == EmptyView {
    init(@ViewBuilder label: @escaping (Bool) -> Label) {
        self.init(additionalContent: { EmptyView() }, label: label)
    }
}
