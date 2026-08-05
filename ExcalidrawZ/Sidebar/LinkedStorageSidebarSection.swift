//
//  LinkedStorageSidebarSection.swift
//  ExcalidrawZ
//

import SwiftUI
#if os(macOS)
import AppKit
#endif

struct LinkedStorageSidebarSection: View {
    @Environment(\.alertToast) private var alertToast
    @Environment(\.containerHorizontalSizeClass) private var containerHorizontalSizeClass
    @AppStorage("ShowLinkedStorageEmptyPlaceholder") private var showEmptyPlaceholder = true
    @StateObject private var connections = CloudStorageConnectionStore.shared
    @State private var pickerContext: CloudStorageFolderPickerContext?
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
                        CloudStorageProviderIcon(providerID: location.providerID, size: 14)
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
        .sheet(item: $pickerContext) { context in
            CloudStorageFolderPicker(context: context) { folder in
                connections.saveLocation(
                    providerID: context.providerID,
                    account: context.account,
                    folder: folder
                )
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
        preparingProviderID = providerID
        Task {
            defer { preparingProviderID = nil }
            do {
                let selection = try await connections.selectLocation(
                    with: providerID,
                    account: connections.accounts(for: providerID).first
                )
                switch selection {
                    case .browse(let account):
                        await preparePicker(providerID: providerID, account: account)
                    case .selected(let account, let folder):
                        connections.saveLocation(
                            providerID: providerID,
                            account: account,
                            folder: folder
                        )
                }
            } catch CloudStorageError.authorizationCancelled {
                return
            } catch {
                alertToast(error)
            }
        }
    }

    private func preparePicker(
        providerID: CloudStorageProviderID,
        account: CloudStorageAccount
    ) async {
        do {
            let session = try await connections.makeSession(
                providerID: providerID,
                account: account
            )
            pickerContext = CloudStorageFolderPickerContext(
                providerID: providerID,
                providerName: descriptor(for: providerID)?.displayName ?? "Cloud Storage",
                account: account,
                session: session
            )
        } catch {
            alertToast(error)
        }
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
                }
            }

        } label: {
            label()
        }
        .menuIndicator(.hidden)
        .fixedSize()
        .modifier(ImportLocalFolderModifier(isPresented: $isImportLocalFolderDialogPresented))
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
        .box,
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
