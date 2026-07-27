//
//  ExcalidrawPresentationModel.swift
//  ExcalidrawZ
//
//  Created by Codex on 2026/7/27.
//

import SwiftUI

@MainActor
final class ExcalidrawPresentationModel: ObservableObject {
    private static let documentLoadTimeout: TimeInterval = 65

    private struct LoadIdentity: Equatable {
        let fileID: String
        let contentChangeToken: Int?
        let colorScheme: ColorScheme
    }

    private struct FramePage {
        let page: ExcalidrawPresentationConfiguration.Page
        let frame: ExcalidrawFrameLikeElement
    }

    enum LoadingState: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    @Published private(set) var slides: [ExcalidrawPresentationSlide] = []
    @Published private(set) var configuration = ExcalidrawPresentationConfiguration()
    @Published private(set) var state: LoadingState = .idle
    @Published var selectedSlideID: String?

    private var loadID = UUID()
    private var representedFileID: String?
    private var loadedIdentity: LoadIdentity?
    private var loadingIdentity: LoadIdentity?

    var isLoading: Bool {
        state == .loading
    }

    var presentationSlides: [ExcalidrawPresentationSlide] {
        slides.filter { !$0.isHidden }
    }

    var initialPresentationSlideID: String? {
        if presentationSlides.contains(where: { $0.id == selectedSlideID }) {
            return selectedSlideID
        }
        return presentationSlides.first?.id
    }

    // MARK: - Loading

    func isRepresenting(fileID: String?) -> Bool {
        fileID != nil && representedFileID == fileID
    }

    func invalidateIfNeeded(for fileID: String?) {
        guard representedFileID != fileID else {
            return
        }

        if loadingIdentity?.fileID != fileID {
            loadID = UUID()
            loadingIdentity = nil
        }
        clearContent(state: fileID == nil ? .idle : .loading)
    }

    func requiresLoad(
        fileID: String?,
        contentChangeToken: Int?,
        colorScheme: ColorScheme
    ) -> Bool {
        guard let fileID else {
            return state != .idle || !slides.isEmpty
        }
        let identity = LoadIdentity(
            fileID: fileID,
            contentChangeToken: contentChangeToken,
            colorScheme: colorScheme
        )

        if state == .loading, loadingIdentity == identity {
            return false
        }

        return representedFileID != fileID ||
            loadedIdentity != identity ||
            state != .loaded
    }

    func load(
        activeFile: FileState.ActiveFile?,
        coordinator: ExcalidrawCore?,
        colorScheme: ColorScheme,
        contentChangeToken: Int?
    ) async -> Bool {
        guard let activeFile, let coordinator else {
            loadID = UUID()
            loadingIdentity = nil
            clearContent(state: .idle)
            return false
        }

        let identity = LoadIdentity(
            fileID: activeFile.id,
            contentChangeToken: contentChangeToken,
            colorScheme: colorScheme
        )
        let currentLoadID = UUID()
        loadID = currentLoadID
        loadingIdentity = identity
        defer {
            if loadID == currentLoadID {
                loadingIdentity = nil
            }
        }
        let isSilentRefresh = identity.fileID == representedFileID && !slides.isEmpty
        var existingImages: [String: PlatformImage] = [:]
        if isSilentRefresh {
            for slide in slides {
                existingImages[slide.id] = slide.image
            }
        }
        let previousSelectedSlideID = selectedSlideID

        if !isSilentRefresh {
            slides = []
        }
        state = .loading

        do {
            if Self.requiresConfirmedDocumentLoad(activeFile) {
                let didLoadFile = try await coordinator.documentSyncController
                    .waitUntilFileIsLoaded(
                        identity.fileID,
                        timeout: Self.documentLoadTimeout
                    )
                guard loadID == currentLoadID else { return false }
                guard didLoadFile else {
                    throw ExcalidrawPresentationError.documentLoadTimedOut
                }
            }

            let snapshot = try await coordinator.getCurrentFileSnapshot(
                includeFiles: false
            )
            try Task.checkCancellation()
            guard loadID == currentLoadID else { return false }
            if Self.requiresConfirmedDocumentLoad(activeFile),
               coordinator.documentSyncController.currentLoadedFileID != identity.fileID {
                return false
            }

            let file = try Self.decodeFile(
                from: snapshot.documentData(includeFiles: false)
            )
            let frames = Self.presentationFrames(in: file)

            let storedConfiguration = await Self.loadConfiguration(
                for: activeFile
            )
            let reconciledConfiguration = storedConfiguration.reconciled(
                withFrameIDs: frames.map(\.id)
            )
            configuration = reconciledConfiguration

            let framePages = Self.framePages(
                configuration: reconciledConfiguration,
                frames: frames
            )

            representedFileID = identity.fileID
            slides = framePages.enumerated().map { index, framePage in
                ExcalidrawPresentationSlide(
                    id: framePage.frame.id,
                    title: Self.title(for: framePage.frame, index: index),
                    isHidden: framePage.page.isHidden,
                    transition: framePage.page.transition,
                    transitionDuration: framePage.page.transitionDuration,
                    speakerNotes: framePage.page.speakerNotes,
                    image: existingImages[framePage.frame.id]
                )
            }
            selectedSlideID = slides.contains { $0.id == previousSelectedSlideID }
                ? previousSelectedSlideID
                : slides.first?.id

            for framePage in framePages {
                try Task.checkCancellation()
                guard loadID == currentLoadID else { return false }

                let frame = framePage.frame
                let frameElements = file.elements.filter {
                    !$0.isDeleted && $0.frameId == frame.id
                }
                let image = try await coordinator.exportElementsPreviewToPNG(
                    elements: frameElements,
                    exportingFrame: frame,
                    files: nil,
                    withBackground: true,
                    colorScheme: colorScheme,
                    exportScale: 1
                )
                guard let slideIndex = slides.firstIndex(where: {
                    $0.id == frame.id
                }) else {
                    continue
                }
                var updatedSlides = slides
                updatedSlides[slideIndex].image = image
                slides = updatedSlides
            }

            guard loadID == currentLoadID else { return false }
            loadedIdentity = identity
            state = .loaded
            return true
        } catch is CancellationError {
            return false
        } catch {
            guard loadID == currentLoadID else { return false }
            state = isSilentRefresh ? .loaded : .failed(error.localizedDescription)
            return false
        }
    }

    // MARK: - Configuration

    func moveSlide(
        _ sourceID: String,
        to targetID: String
    ) {
        guard sourceID != targetID,
              let sourceIndex = configuration.pages.firstIndex(where: {
                  $0.frameID == sourceID
              }),
              configuration.pages.contains(where: {
                  $0.frameID == targetID
              }) else {
            return
        }

        var pages = configuration.pages
        guard let targetIndex = pages.firstIndex(where: {
            $0.frameID == targetID
        }) else {
            return
        }
        pages.move(
            fromOffsets: IndexSet(integer: sourceIndex),
            toOffset: targetIndex > sourceIndex ? targetIndex + 1 : targetIndex
        )
        configuration.pages = pages
        applyConfigurationOrderToSlides()
    }

    func setTransition(
        _ transition: ExcalidrawPresentationConfiguration.Transition,
        for slideID: String
    ) {
        guard let pageIndex = configuration.pages.firstIndex(where: {
            $0.frameID == slideID
        }) else {
            return
        }
        configuration.pages[pageIndex].transition = transition

        guard let slideIndex = slides.firstIndex(where: {
            $0.id == slideID
        }) else {
            return
        }
        slides[slideIndex].transition = transition
    }

    func setTransitionDuration(
        _ duration: TimeInterval,
        for slideID: String
    ) {
        let duration = min(max(duration, 0.1), 3)
        guard let pageIndex = configuration.pages.firstIndex(where: {
            $0.frameID == slideID
        }) else {
            return
        }
        configuration.pages[pageIndex].transitionDuration = duration

        guard let slideIndex = slides.firstIndex(where: {
            $0.id == slideID
        }) else {
            return
        }
        slides[slideIndex].transitionDuration = duration
    }

    func persistConfiguration(
        _ configuration: ExcalidrawPresentationConfiguration,
        for activeFile: FileState.ActiveFile?
    ) async throws {
        guard let reference = Self.persistenceReference(for: activeFile) else {
            return
        }
        try await PersistenceController.shared
            .presentationConfigurationRepository
            .save(configuration, for: reference)
    }

    // MARK: - Helpers

    private func clearContent(state newState: LoadingState) {
        representedFileID = nil
        loadedIdentity = nil
        slides = []
        configuration = ExcalidrawPresentationConfiguration()
        selectedSlideID = nil
        state = newState
    }

    private func applyConfigurationOrderToSlides() {
        let slidesByID = Dictionary(
            uniqueKeysWithValues: slides.map { ($0.id, $0) }
        )
        slides = configuration.pages.compactMap {
            slidesByID[$0.frameID]
        }
    }

    private static func requiresConfirmedDocumentLoad(
        _ activeFile: FileState.ActiveFile
    ) -> Bool {
        if case .collaborationFile = activeFile {
            return false
        }
        return true
    }

    private static func presentationFrames(
        in file: ExcalidrawFile
    ) -> [ExcalidrawFrameLikeElement] {
        file.elements.compactMap { element in
            guard case .frameLike(let frame) = element,
                  frame.type == .frame,
                  !frame.isDeleted else {
                return nil
            }
            return frame
        }
    }

    private static func framePages(
        configuration: ExcalidrawPresentationConfiguration,
        frames: [ExcalidrawFrameLikeElement]
    ) -> [FramePage] {
        let framesByID = Dictionary(
            uniqueKeysWithValues: frames.map { ($0.id, $0) }
        )
        return configuration.pages.compactMap { page in
            guard let frame = framesByID[page.frameID] else {
                return nil
            }
            return FramePage(page: page, frame: frame)
        }
    }

    private static func loadConfiguration(
        for activeFile: FileState.ActiveFile?
    ) async -> ExcalidrawPresentationConfiguration {
        guard let reference = persistenceReference(for: activeFile) else {
            return ExcalidrawPresentationConfiguration()
        }
        return (try? await PersistenceController.shared
            .presentationConfigurationRepository
            .load(for: reference)) ?? ExcalidrawPresentationConfiguration()
    }

    private static func persistenceReference(
        for activeFile: FileState.ActiveFile?
    ) -> ExcalidrawPresentationFileReference? {
        switch activeFile {
            case .file(let file):
                .libraryFile(objectURI: file.objectID.uriRepresentation())
            case .collaborationFile(let file):
                .collaborationFile(objectURI: file.objectID.uriRepresentation())
            case .localFile, .temporaryFile, nil:
                nil
        }
    }

    private static func title(
        for frame: ExcalidrawFrameLikeElement,
        index: Int
    ) -> String {
        let name = frame.name?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let name, !name.isEmpty {
            return name
        }
        return String(localizable: .presentationUntitledSlide(Int(index + 1)))
    }

    private static func decodeFile(from data: Data) throws -> ExcalidrawFile {
        guard var object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ExcalidrawPresentationError.invalidSnapshot
        }
        object["type"] = object["type"] ?? "excalidraw"
        object["source"] = object["source"] ?? "https://excalidraw.com"
        object["version"] = object["version"] ?? 2
        return try ExcalidrawFile(
            data: JSONSerialization.data(withJSONObject: object)
        )
    }
}

private enum ExcalidrawPresentationError: LocalizedError {
    case invalidSnapshot
    case documentLoadTimedOut

    var errorDescription: String? {
        String(localizable: .presentationLoadFailed)
    }
}
