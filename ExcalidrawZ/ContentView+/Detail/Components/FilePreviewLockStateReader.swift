import SwiftUI

private struct FilePreviewLockStateStoreKey: EnvironmentKey {
    static let defaultValue: LockedContentStateStore? = nil
}

extension EnvironmentValues {
    /// A service reference, without subscribing each card to the whole store.
    var filePreviewLockStateStore: LockedContentStateStore? {
        get { self[FilePreviewLockStateStoreKey.self] }
        set { self[FilePreviewLockStateStoreKey.self] = newValue }
    }
}

/// Observes only this file's derived protection state. Other file resolutions
/// and editor-only state changes do not invalidate the preview content.
struct FilePreviewLockStateReader<Content: View>: View {
    @Environment(\.filePreviewLockStateStore) private var store

    let file: FileState.ActiveFile
    let requestsMetadataIfUnknown: Bool
    @ViewBuilder let content: (FileContentLockState?) -> Content

    init(
        file: FileState.ActiveFile,
        requestsMetadataIfUnknown: Bool = true,
        @ViewBuilder content: @escaping (FileContentLockState?) -> Content
    ) {
        self.file = file
        self.requestsMetadataIfUnknown = requestsMetadataIfUnknown
        self.content = content
    }

    @ViewBuilder
    var body: some View {
        if case .file = file {
            if let store {
                ObservedFilePreviewLockState(
                    file: file,
                    store: store,
                    state: store.previewState(for: file),
                    requestsMetadataIfUnknown: requestsMetadataIfUnknown,
                    content: content
                )
                .id(file.id)
            } else {
                // Protection metadata must be known before revealing a cover.
                content(nil)
            }
        } else {
            content(.plaintext)
        }
    }
}

private struct ObservedFilePreviewLockState<Content: View>: View {
    let file: FileState.ActiveFile
    let store: LockedContentStateStore
    @ObservedObject var state: FilePreviewLockState
    let requestsMetadataIfUnknown: Bool
    @ViewBuilder let content: (FileContentLockState?) -> Content

    @ViewBuilder
    var body: some View {
        if requestsMetadataIfUnknown {
            content(state.value)
                .task(id: state.value == nil) {
                    guard state.value == nil else { return }
                    await store.refresh(file: file)
                }
        } else {
            content(state.value)
        }
    }
}
