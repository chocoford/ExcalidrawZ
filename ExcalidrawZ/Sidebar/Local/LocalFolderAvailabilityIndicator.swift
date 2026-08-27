import CoreData
import SFSafeSymbols
import SwiftUI

extension Notification.Name {
    static let localFolderAvailabilityDidChange = Notification.Name(
        "localFolderAvailabilityDidChange"
    )
}

/// Reports materialization of a Linked Folder supplied by iCloud Drive or
/// another Files provider. A successful download asks active file browsers to
/// enumerate the folder again.
@MainActor
struct LocalFolderAvailabilityIndicator: View {
    @Environment(\.scenePhase) private var scenePhase

    let folder: LocalFolder

    @State private var status: ICloudFileStatus?

    var body: some View {
        ZStack {
            switch status {
                case .notDownloaded, .outdated:
                    statusIcon(.icloudAndArrowDown)
                case .downloading:
                    ProgressView()
                        .controlSize(.mini)
                        .frame(width: 16, height: 16)
                case .error:
                    statusIcon(.exclamationmarkTriangle)
                default:
                    EmptyView()
            }
        }
        .task(id: monitorID) {
            await monitorAvailability()
        }
    }

    private var monitorID: String {
        "\(folder.filePath ?? folder.objectID.uriRepresentation().absoluteString)|\(scenePhase)"
    }

    private func statusIcon(_ symbol: SFSymbol) -> some View {
        Image(systemSymbol: symbol)
            .foregroundStyle(.secondary)
            .font(.footnote)
            .frame(width: 16, height: 16)
    }

    private func monitorAvailability() async {
        var wasWaitingForDownload = false

        for _ in 0..<40 where !Task.isCancelled {
            do {
                let nextStatus = try await folder.withSecurityScopedURL { url in
                    let checkedStatus = try await ICloudStatusChecker.shared.checkStatus(for: url)
                    if checkedStatus == .notDownloaded || checkedStatus == .outdated {
                        try FileManager.default.startDownloadingUbiquitousItem(at: url)
                        return ICloudFileStatus.downloading(progress: nil)
                    }
                    return checkedStatus
                }

                status = nextStatus
                if nextStatus.isInProgress {
                    wasWaitingForDownload = true
                    try await Task.sleep(nanoseconds: 750_000_000)
                    continue
                }

                if wasWaitingForDownload, nextStatus.isAvailable {
                    NotificationCenter.default.post(
                        name: .localFolderAvailabilityDidChange,
                        object: folder.objectID
                    )
                }
                return
            } catch is CancellationError {
                return
            } catch {
                status = .error(error.localizedDescription)
                return
            }
        }
    }
}
