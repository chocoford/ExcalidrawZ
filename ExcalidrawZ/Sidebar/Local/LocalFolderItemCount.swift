import SwiftUI
import CoreData

/// Folder tiles must not enumerate their directory from a body/init on the UI thread.
struct LocalFolderItemCount<Content: View>: View {
    let folder: LocalFolder?
    let fallbackCount: Int
    @ViewBuilder let content: (Int) -> Content
    @State private var count: Int?
    @State private var revision = 0

    var body: some View {
        content(count ?? fallbackCount)
            .task(id: "\(folder?.objectID.uriRepresentation().absoluteString ?? ""):\(folder?.filePath ?? ""):\(revision)") {
                guard let folder else { return }
                let id = folder.objectID
                let loaded = try? await LinkedFolderDirectoryLoader.shared.itemCount(in: id)
                if !Task.isCancelled, let loaded { count = loaded }
            }
            .onReceive(NotificationCenter.default.publisher(for: .linkedFolderContentsDidChange)) { notification in
                if LinkedFolderIndexState.affects(notification, folderURL: folder?.url) { revision += 1 }
            }
    }
}
