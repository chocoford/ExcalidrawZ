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
        onChange: @escaping (FileStatus) -> Void
    ) -> some View {
        background {
            if let activeFile {
                FileStatusObserverView(file: activeFile, onChange: onChange)
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

struct FileStatusProvider: View {

    var file: FileState.ActiveFile?
    var content: (FileStatus?) -> AnyView

    init<Content: View>(
        file: FileState.ActiveFile?,
        @ViewBuilder content: @escaping (FileStatus?) -> Content
    ) {
        self.file = file
        self.content = {
            AnyView(content($0))
        }
    }

    @State private var fileStatus: FileStatus?

    var body: some View {
        content(fileStatus)
            .bindFileStatus(for: file, status: $fileStatus)
    }
}

private struct FileStatusObserverView: View {
    @ObservedObject private var fileStatusBox: FileStatusBox
    var file: FileState.ActiveFile
    var onChange: (FileStatus) -> Void

    init(file: FileState.ActiveFile, onChange: @escaping (FileStatus) -> Void) {
        self.file = file
        self.fileStatusBox = FileStatusService.shared.statusBox(for: file)
        self.onChange = onChange
    }

    @State private var oldValue: FileStatus?

    var body: some View {
        Color.clear
            .onReceive(fileStatusBox.$status) { newValue in
                print("[DEBUG] Receive fileStatusBox.$status", file.id, newValue)
                guard oldValue != newValue else { return }
                onChange(newValue)
                oldValue = newValue
            }
    }
}
