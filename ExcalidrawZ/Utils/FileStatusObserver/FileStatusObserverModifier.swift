//
//  FileStatusObserverModifier.swift
//  ExcalidrawZ
//
//  Created by Chocoford on 12/31/25.
//

import SwiftUI
import Combine


extension View {
    /// Observe file status changes for the active file
    /// - Parameters:
    ///   - activeFile: The active file to observe
    ///   - onChange: Closure called when status changes
    /// - Returns: Modified view
    @ViewBuilder
    func observeFileStatus(
        for activeFile: FileState.ActiveFile?,
        onlyICloudStatusChanges: Bool = false,
        onChange: @escaping (FileStatus) -> Void
    ) -> some View {
        background {
            if let activeFile {
                FileStatusObserverView(
                    file: activeFile,
                    onlyICloudStatusChanges: onlyICloudStatusChanges,
                    onChange: onChange
                )
            }
        }
    }

    @ViewBuilder
    func bindFileStatus(
        for activeFile: FileState.ActiveFile?,
        status: Binding<FileStatus?>
    ) -> some View {
        observeFileStatus(for: activeFile) { s in
            status.wrappedValue = s
        }
    }
}

struct FileStatusProvider<Content: View>: View {
    private let fileStatusBox: FileStatusBox?
    private let content: (FileStatus?) -> Content

    init(
        file: FileState.ActiveFile?,
        @ViewBuilder content: @escaping (FileStatus?) -> Content
    ) {
        if let file {
            self.fileStatusBox = FileStatusService.shared.statusBox(for: file)
        } else {
            self.fileStatusBox = nil
        }
        self.content = content
    }

    @ViewBuilder
    var body: some View {
        if let fileStatusBox {
            FileStatusProviderContent(fileStatusBox: fileStatusBox, content: content)
        } else {
            content(nil)
        }
    }
}

/// Read the existing per-file state directly. No mirrored @State, initial
/// publisher callback or transparent observer background is needed here.
private struct FileStatusProviderContent<Content: View>: View {
    @ObservedObject var fileStatusBox: FileStatusBox
    let content: (FileStatus?) -> Content

    var body: some View {
        content(fileStatusBox.status)
    }
}

private struct FileStatusObserverView: View {
    private let fileStatusBox: FileStatusBox
    private let onlyICloudStatusChanges: Bool
    var file: FileState.ActiveFile
    var onChange: (FileStatus) -> Void

    init(
        file: FileState.ActiveFile,
        onlyICloudStatusChanges: Bool,
        onChange: @escaping (FileStatus) -> Void
    ) {
        self.file = file
        self.fileStatusBox = FileStatusService.shared.statusBox(for: file)
        self.onlyICloudStatusChanges = onlyICloudStatusChanges
        self.onChange = onChange
    }

    // Callback bookkeeping does not affect rendering. Keep it in a stable
    // reference so receiving an initial status doesn't invalidate this view.
    @State private var deliveryState = FileStatusDeliveryState()

    var body: some View {
        Color.clear
            .onReceive(fileStatusBox.$status) { newValue in
                guard deliveryState.shouldDeliver(
                    newValue,
                    fileID: file.id,
                    onlyICloudStatusChanges: onlyICloudStatusChanges
                ) else { return }
                onChange(newValue)
            }
    }
}

private final class FileStatusDeliveryState {
    private var fileID: String?
    private var status: FileStatus?

    func shouldDeliver(
        _ newStatus: FileStatus,
        fileID newFileID: String,
        onlyICloudStatusChanges: Bool
    ) -> Bool {
        let changed = onlyICloudStatusChanges
            ? status?.iCloudStatus != newStatus.iCloudStatus
            : status != newStatus
        guard fileID != newFileID || changed else { return false }
        fileID = newFileID
        status = newStatus
        return true
    }
}
