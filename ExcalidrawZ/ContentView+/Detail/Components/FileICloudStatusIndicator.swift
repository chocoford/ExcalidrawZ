//
//  FileICloudStatusIndicator.swift
//  ExcalidrawZ
//
//  Created by Chocoford on 1/3/26.
//

import SwiftUI

struct FileICloudStatusIndicator: View {
    var file: FileState.ActiveFile
    
    var downloadedFallbackView: AnyView?
    
    init<Content: View>(
        file: FileState.ActiveFile,
        @ViewBuilder downloadedFallbackView: () -> Content
    ) {
        self.file = file
        self.downloadedFallbackView = AnyView(downloadedFallbackView())
    }
    
    init(
        file: FileState.ActiveFile,
    ) {
        self.file = file
    }
    
    @State private var fileStatus: FileStatus? = nil

    var body: some View {
        ZStack {
            if #available(macOS 26.0, iOS 26.0, *) {
                switch fileStatus?.iCloudStatus {
                    case .notDownloaded:
                        Image(systemSymbol: .icloudAndArrowDown)
                            .symbolEffect(.drawOn, options: .speed(2), isActive: fileStatus?.iCloudStatus == .notDownloaded)
                    case .downloading(let progress):
                        CircularProgressIndicator(progress: progress ?? 0)
                    case .downloaded:
                        downloadedFallbackView
                            .symbolEffect(.drawOn, options: .speed(2), isActive: fileStatus?.iCloudStatus == .downloaded)
                    case .outdated:
                        Image(systemName: "icloud.dashed")
                    case .loading:
                        ProgressView()
                    case .local:
                        EmptyView()
                    case .uploading:
                        Image(systemSymbol: .icloudAndArrowUp)
                            .symbolEffect(.drawOn, options: .speed(2), isActive: fileStatus?.iCloudStatus == .uploading)
                    case .conflict:
                        Image(systemSymbol: .xmarkIcloud)
                            .symbolEffect(.drawOn, options: .speed(2), isActive: fileStatus?.iCloudStatus == .conflict)
                    case .error(_):
                        Image(systemSymbol: .exclamationmarkTriangle)
                            .symbolEffect(.drawOn, options: .speed(2), isActive: {
                                if case .error = fileStatus?.iCloudStatus {
                                    return true
                                }
                                return false
                            }())
                    default:
                        EmptyView()
                }
            } else {
                switch fileStatus?.iCloudStatus {
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
                    default:
                        EmptyView()
                }
            }
        }
        .bindFileStatus(for: file, status: $fileStatus)
        .symbolRenderingMode(.multicolor)
        .animation(.smooth, value: fileStatus?.iCloudStatus)
    }
}
