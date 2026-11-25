import SwiftUI
import CoreData
import ChocofordUI

struct SidebarFileReveal: Equatable {
    let file: SidebarActiveFileScrollTarget
    let folders: [SidebarGroupScrollTarget]
    let showsFileRow: Bool

    @MainActor
    init?(fileState: FileState, folderStyle: FolderStructureStyle) {
        guard let activeFile = fileState.currentActiveFile,
              let file = SidebarActiveFileScrollTarget(activeFile: activeFile) else { return nil }
        self.file = file

        switch activeFile {
            case .file(let document):
                let parent: Group?
                if document.inTrash {
                    if case .group(let group) = fileState.currentActiveGroup, group.groupType == .trash {
                        parent = group
                    } else {
                        return nil
                    }
                } else {
                    parent = document.group
                }
                guard let parent else { return nil }
                folders = Self.path(to: parent, makeTarget: SidebarGroupScrollTarget.group)
                showsFileRow = folderStyle == .disclosureGroup
            case .localFile(let url):
                guard case .localFolder(let folder) = fileState.currentActiveGroup,
                      let path = folder.filePath,
                      URL(fileURLWithPath: path).standardizedFileURL.path
                        == url.deletingLastPathComponent().standardizedFileURL.path else {
                    return nil
                }
                folders = Self.path(to: folder, makeTarget: SidebarGroupScrollTarget.localFolder)
                showsFileRow = folderStyle == .disclosureGroup
            case .cloudStorageFile(let reference):
                let store = CloudStorageDocumentStore.shared
                guard let parent = store.bestKnownParentFolder(for: reference) else { return nil }
                folders = store.folderPath(for: parent).map {
                    .cloudStorageFolder(locationID: $0.location.id, itemID: $0.itemID)
                }
                showsFileRow = true
            case .temporaryFile:
                guard !fileState.temporaryFiles.isEmpty else { return nil }
                folders = [.temporary]
                showsFileRow = false
            case .collaborationFile:
                folders = [.collaboration]
                showsFileRow = false
        }
    }

    var firstStep: SidebarFileRevealStep? {
        folders.first.map { SidebarFileRevealStep(reveal: self, index: 0, destination: .folder($0)) }
    }

    func nextStep(
        after folder: SidebarGroupScrollTarget,
        containsFolder: (SidebarGroupScrollTarget) -> Bool,
        fileAvailable: Bool
    ) -> SidebarFileRevealStep? {
        guard let index = folders.firstIndex(of: folder) else { return nil }
        let nextIndex = index + 1
        if nextIndex < folders.count {
            let child = folders[nextIndex]
            guard containsFolder(child) else { return nil }
            return SidebarFileRevealStep(reveal: self, index: nextIndex, destination: .folder(child))
        }
        guard showsFileRow, fileAvailable else { return nil }
        return SidebarFileRevealStep(reveal: self, index: nextIndex, destination: .file(file))
    }

    private static func path(
        to folder: any ExcalidrawGroup,
        makeTarget: (NSManagedObjectID) -> SidebarGroupScrollTarget
    ) -> [SidebarGroupScrollTarget] {
        var folders: [SidebarGroupScrollTarget] = []
        var visited = Set<NSManagedObjectID>()
        var current: (any ExcalidrawGroup)? = folder
        while let folder = current, visited.insert(folder.objectID).inserted {
            folders.append(makeTarget(folder.objectID))
            current = folder.getParent() as? any ExcalidrawGroup
        }
        return folders.reversed()
    }
}

struct SidebarFileRevealStep: Equatable {
    enum Destination: Equatable {
        case folder(SidebarGroupScrollTarget)
        case file(SidebarActiveFileScrollTarget)
    }

    let reveal: SidebarFileReveal
    let index: Int
    let destination: Destination
}

struct SidebarFileRevealStepPreference: PreferenceKey {
    static let defaultValue: SidebarFileRevealStep? = nil

    static func reduce(value: inout SidebarFileRevealStep?, nextValue: () -> SidebarFileRevealStep?) {
        guard let next = nextValue() else { return }
        if next.index > (value?.index ?? -1) {
            value = next
        }
    }
}

private struct SidebarFileRevealKey: EnvironmentKey {
    static let defaultValue: SidebarFileReveal? = nil
}

extension EnvironmentValues {
    var sidebarFileReveal: SidebarFileReveal? {
        get { self[SidebarFileRevealKey.self] }
        set { self[SidebarFileRevealKey.self] = newValue }
    }
}

private struct SidebarFileRevealFolderModifier: ViewModifier {
    private enum Target: Equatable {
        case file(SidebarActiveFileScrollTarget)
        case folder(String)
    }

    @Environment(\.sidebarFileReveal) private var reveal
    let folder: SidebarGroupScrollTarget
    @Binding var isExpanded: Bool
    let selectedFolderID: String?

    func body(content: Content) -> some View {
        let target: Target? = if let reveal, reveal.folders.contains(folder) {
            .file(reveal.file)
        } else {
            selectedFolderID.map(Target.folder)
        }
        content.watch(value: target, initial: true) { target in
            guard target != nil, !isExpanded else { return }
            withAnimation(.smooth(duration: 0.2)) { isExpanded = true }
        }
    }
}

private struct SidebarFileRevealContentsModifier: ViewModifier {
    @Environment(\.sidebarFileReveal) private var reveal
    let folder: SidebarGroupScrollTarget
    let available: Bool
    let fileAvailable: Bool
    let containsFolder: (SidebarGroupScrollTarget) -> Bool

    func body(content: Content) -> some View {
        let step = available ? reveal?.nextStep(after: folder, containsFolder: containsFolder, fileAvailable: fileAvailable) : nil
        content.transformPreference(SidebarFileRevealStepPreference.self) { value in
            SidebarFileRevealStepPreference.reduce(value: &value) { step }
        }
    }
}

extension View {
    func expandForSidebarFileReveal(
        _ folder: SidebarGroupScrollTarget,
        isExpanded: Binding<Bool>,
        selectedFolderID: String? = nil
    ) -> some View {
        modifier(SidebarFileRevealFolderModifier(folder: folder, isExpanded: isExpanded, selectedFolderID: selectedFolderID))
    }

    func reportSidebarFileRevealContents(
        of folder: SidebarGroupScrollTarget,
        available: Bool = true,
        fileAvailable: Bool = false,
        containsFolder: @escaping (SidebarGroupScrollTarget) -> Bool = { _ in false }
    ) -> some View {
        modifier(SidebarFileRevealContentsModifier(
            folder: folder,
            available: available,
            fileAvailable: fileAvailable,
            containsFolder: containsFolder
        ))
    }
}
