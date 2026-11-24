//
//  GoogleDriveAuthorizationButton.swift
//  ExcalidrawZ
//

import SwiftUI
import SwiftyAlert

/// Shared by the dismissible hint and transient folder menus.
struct GoogleDriveAuthorizationButton<Label: View>: View {
    @Environment(\.alertToast) private var alertToast
    @State private var connections = CloudStorageConnectionStore.shared
    @State private var isExecuting = false

    let location: CloudStorageLocation
    let parentID: CloudStorageItemID
    private let label: (Bool) -> Label

    init(
        location: CloudStorageLocation,
        parentID: CloudStorageItemID,
        @ViewBuilder label: @escaping (Bool) -> Label
    ) {
        self.location = location
        self.parentID = parentID
        self.label = label
    }

    var body: some View {
        Button(action: authorize) {
            label(isWorking)
        }
        .disabled(isWorking)
        .accessibilityIdentifier("google-drive-authorize-more")
    }

    private var isWorking: Bool {
        isExecuting || connections.connectingProviderIDs.contains(.googleDrive)
    }

    private func authorize() {
        guard !isWorking, location.providerID == .googleDrive else { return }
        isExecuting = true
        // A menu disappears immediately after selection. Keep its explicit
        // authorization running independently of the menu view's lifetime.
        Task { @MainActor in
            defer { isExecuting = false }
            do {
                try await connections.authorizeAdditionalGoogleDriveItems(in: location)
                try Task.checkCancellation()
                CloudStorageDocumentStore.shared.invalidateSession(for: location.id)
                await CloudStorageSyncService.shared.prioritizeDocuments(
                    in: location,
                    parentID: parentID,
                    connections: connections,
                    reloadAfterCurrent: true
                )
                try Task.checkCancellation()
                if let error = CloudStorageDocumentStore.shared.errorMessage(for: location) {
                    alertToast(CloudStorageError.transport(error))
                }
            } catch CloudStorageError.authorizationCancelled {
                return
            } catch is CancellationError {
                return
            } catch {
                if !Task.isCancelled {
                    alertToast(error)
                }
            }
        }
    }
}

struct GoogleDriveAuthorizationMenuItem: View {
    let location: CloudStorageLocation
    var parentID: CloudStorageItemID?

    var body: some View {
        if location.providerID == .googleDrive {
            GoogleDriveAuthorizationButton(location: location, parentID: parentID ?? location.rootItemID) { _ in
                Label(.localizable(.cloudStorageGoogleDriveAuthorizeMoreAction), systemImage: "folder.badge.plus")
            }
        }
    }
}
