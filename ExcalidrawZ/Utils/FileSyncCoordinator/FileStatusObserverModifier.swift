//
//  FileStatusObserverModifier.swift
//  ExcalidrawZ
//
//  Created by Claude on 12/25/25.
//

import SwiftUI
import Combine

// MARK: - View Extension

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
            if case .localFile(let url) = activeFile {
                FileStatusObserverView(url: url, onChange: onChange)
                    .id(url)
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
    var onChange: (FileStatus) -> Void
    
    init(url: URL, onChange: @escaping (FileStatus) -> Void) {
        self.fileStatusBox = FileSyncCoordinator.shared.statusBox(for: url)
        self.onChange = onChange
    }
    
    @State private var oldValue: FileStatus?

    var body: some View {
        Color.clear
            .onReceive(fileStatusBox.$status) { newValue in
                guard oldValue != newValue else { return }
                onChange(newValue)
                oldValue = newValue
            }
    }
}
