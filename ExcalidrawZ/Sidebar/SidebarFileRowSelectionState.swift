import CoreData
import Foundation
import Observation

@MainActor
@Observable
final class SidebarFileRowSelectionState {
    private(set) var isSelected = false
    private(set) var isMultiSelected = false

    @ObservationIgnored private var fileObjectID: NSManagedObjectID?
    @ObservationIgnored private weak var boundFileState: FileState?
    @ObservationIgnored private var selectionObservation: ObservationSubscription?

    func bind(file: File, fileState: FileState) {
        guard fileObjectID != file.objectID || boundFileState !== fileState else { return }
        selectionObservation?.cancel()
        fileObjectID = file.objectID
        boundFileState = fileState
        let objectID = file.objectID
        selectionObservation = ObservationSubscription { [weak fileState] in
            guard let fileState else { return [false, false] }
            let isSelected: Bool
            if case .file(let activeFile) = fileState.currentActiveFile {
                isSelected = activeFile.objectID == objectID
            } else {
                isSelected = false
            }
            return [isSelected, fileState.selectedFiles.contains { $0.objectID == objectID }]
        } onChange: { [weak self] selection in
            self?.isSelected = selection[0]
            self?.isMultiSelected = selection[1]
        }
    }
}

@MainActor
@Observable
final class SidebarGroupRowSelectionState {
    private(set) var isSelected = false

    @ObservationIgnored private var groupObjectID: NSManagedObjectID?
    @ObservationIgnored private weak var boundFileState: FileState?
    @ObservationIgnored private var selectionObservation: ObservationSubscription?

    func bind(group: Group, fileState: FileState) {
        guard groupObjectID != group.objectID || boundFileState !== fileState else { return }
        selectionObservation?.cancel()
        groupObjectID = group.objectID
        boundFileState = fileState
        let objectID = group.objectID
        selectionObservation = ObservationSubscription { [weak fileState] in
            guard let fileState else { return false }
            if case .group(let activeGroup) = fileState.currentActiveGroup,
               fileState.currentActiveFile == nil {
                return activeGroup.objectID == objectID
            }
            return false
        } onChange: { [weak self] isSelected in
            self?.isSelected = isSelected
        }
    }
}

@MainActor
@Observable
final class SidebarLocalFileRowSelectionState {
    private(set) var isSelected = false
    private(set) var isMultiSelected = false

    @ObservationIgnored private var file: URL?
    @ObservationIgnored private weak var boundFileState: FileState?
    @ObservationIgnored private var selectionObservation: ObservationSubscription?

    func bind(file: URL, fileState: FileState) {
        guard self.file != file || boundFileState !== fileState else { return }
        selectionObservation?.cancel()
        self.file = file
        boundFileState = fileState
        selectionObservation = ObservationSubscription { [weak fileState] in
            guard let fileState else { return [false, false] }
            let isSelected: Bool
            if case .localFile(let activeFile) = fileState.currentActiveFile {
                isSelected = activeFile == file
            } else {
                isSelected = false
            }
            return [isSelected, fileState.selectedLocalFiles.contains(file)]
        } onChange: { [weak self] selection in
            self?.isSelected = selection[0]
            self?.isMultiSelected = selection[1]
        }
    }
}
