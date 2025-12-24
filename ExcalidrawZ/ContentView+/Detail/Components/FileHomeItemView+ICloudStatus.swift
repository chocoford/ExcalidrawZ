//
//  FileHomeItemView+ICloudStatus.swift
//  ExcalidrawZ
//
//  Created by Chocoford on 12/22/25.
//

import SwiftUI


private struct LocalFileICloudStatusEnvironmentKey: EnvironmentKey {
    static var defaultValue: FileStatus = .local
}

private extension EnvironmentValues {
    var iCloudFileStatus: FileStatus {
        get { self[LocalFileICloudStatusEnvironmentKey.self] }
        set { self[LocalFileICloudStatusEnvironmentKey.self] = newValue }
    }
}

struct FileHomeItemICloudStatusProvider: ViewModifier {
    @EnvironmentObject private var localFolderState: LocalFolderState
    
    var file: FileState.ActiveFile
    
    func body(content: Content) -> some View {
        if case .localFile(let url) = file {
            content
                .modifier(FileHomeItemICloudStatusProviderContent(url: url))
        } else {
            content
        }
    }
    
}

struct FileHomeItemICloudStatusProviderContent: ViewModifier {
    @ObservedObject private var fileStatusBox: FileStatusBox
    
    init(url: URL) {
        self.fileStatusBox = FileSyncCoordinator.shared.statusBox(for: url)
    }
    
    func body(content: Content) -> some View {
        content
            .environment(
                \.iCloudFileStatus,
                 fileStatusBox.status
            )
    }
}

struct FileICloudStatusProvider: View {
    @Environment(\.iCloudFileStatus) private var iCloudFileStatus

    var content: (FileStatus) -> AnyView
    
    init<Content: View>(
        @ViewBuilder content: @escaping (FileStatus) -> Content
    ) {
        self.content = { status in
            AnyView(content(status))
        }
    }
    
    var body: some View {
        content(iCloudFileStatus)
    }
}

struct FileICloudStatusIndicator: View {
    @Environment(\.iCloudFileStatus) private var iCloudFileStatus
    
    var downloadedFallbackView: AnyView?
    
    init<Content: View>(@ViewBuilder downloadedFallbackView: () -> Content) {
        self.downloadedFallbackView = AnyView(downloadedFallbackView())
    }
    
    init() { }
    
    var body: some View {
        ZStack {
            switch iCloudFileStatus {
                case .notDownloaded:
                    Image(systemSymbol: .icloudAndArrowDown)
                case .downloading(let progress):
                    CircularProgressIndicator(progress: progress ?? 0)
                case .downloaded:
                    downloadedFallbackView
                case .outdated:
                    Image(systemName: "icloud.dashed")
                case .loading:
                    ProgressView()
                case .local:
                    EmptyView()
                case .uploading:
                    Image(systemSymbol: .icloudAndArrowUp)
                case .conflict:
                    Image(systemSymbol: .xmarkIcloud)
                case .error(_):
                    Image(systemSymbol: .exclamationmarkTriangle)

            }
        }
    }
}
