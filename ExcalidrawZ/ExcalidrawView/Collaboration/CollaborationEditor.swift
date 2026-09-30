//
//  CollaborationEditor.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 3/17/25.
//

import SwiftUI
import CoreData
import SwiftyAlert

import ChocofordUI

struct CollaborationEditor: View {
    @Environment(\.managedObjectContext) var viewContext
    @Environment(\.alertToast) var alertToast
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject var appPreference: AppPreference
    @EnvironmentObject var fileState: FileState
    @EnvironmentObject private var collaborationState: CollaborationState
    @EnvironmentObject private var fileHomeItemTransitionState: FileHomeItemTransitionState

    var file: CollaborationFile

    init(file: CollaborationFile) {
        self.file = file
    }
    
    var isActive: Bool {
        if fileState.isInCollaborationSpace,
           case .collaborationFile(let room) = fileState.currentActiveFile {
            return room == file
        } else {
            return false
        }
    }
    
    @State private var loadingState: ExcalidrawCanvasView.LoadingState = .idle
    @State private var isProgressViewPresented = true

    @State private var excalidrawFile: ExcalidrawFile?
    @State private var loadedContent: Data?
    @State private var loadedRoomID: String?
    @State private var didShowRoomSyncNotice = false
    @State private var isRoomSyncNoticePresented = false
    @State private var roomSyncNoticeTask: Task<Void, Never>?
    @State private var loadingOverlayCoverImage: PlatformImage?

    var body: some View {
        ZStack {
            if excalidrawFile != nil {
                ExcalidrawCanvasView(
                    type: .collaboration,
                    file: $excalidrawFile,
                    loadingState: $loadingState,
                    interactionEnabled: isActive && canShowCanvasContent
                ) { error in
                    alertToast(error)
                }
                .preferredColorScheme(appPreference.excalidrawAppearance.colorScheme)
                .opacity(isProgressViewPresented || !canShowCanvasContent ? 0 : 1)
                .onChange(of: loadingState, debounce: 0.3) { newVal in
                    isProgressViewPresented = newVal == .loading
                    if newVal == .loading {
                        loadingOverlayCoverImage = loadingCoverImage
                    } else {
                        loadingOverlayCoverImage = nil
                    }
                    
                    fileState.collaboratingFilesState[file] = newVal
                    
                    if newVal == .loaded {
                        showRoomSyncNoticeIfNeeded()
                        Task {
                            do {
                                try await fileState.excalidrawCollaborationWebCoordinator?
                                    .setCollaborationInfo(
                                        collaborationState.userCollaborationInfo
                                    )
                            } catch {
                                alertToast(error)
                            }
                        }
                    }
                }
                .onChange(of: collaborationState.userCollaborationInfo, debounce: 1.0) { newInfo in
                    Task {
                        do {
                            try await fileState.excalidrawCollaborationWebCoordinator?.setCollaborationInfo(
                                newInfo
                            )
                        } catch {
                            alertToast(error)
                        }
                    }
                }
                .onChange(of: excalidrawFile, throttle: 1.0, latest: true) { newValue in
                    guard let newValue, loadingState == .loaded else { return }
                    guard let content = newValue.content else { return }
                    guard content != loadedContent || newValue.roomID != loadedRoomID else { return }
                    fileState.updateCollaborationFile(file, with: newValue)
                }
            }
            
            if case .error(let error) = loadingState, canShowCanvasContent {
                Color(red: 255 / 255.0, green: 200 / 255.0, blue: 200 / 255.0, opacity: 1.0)
                    .overlay {
                        VStack(spacing: 20) {
                            Image(systemSymbol: .xmark)
                                .resizable()
                                .scaledToFit()
                                .symbolVariant(.circle)
                                .foregroundStyle(.red)
                                .frame(height: 80)
                            
                            Text("Load failed.")
                                .font(.title)
                            if let error = error as? LocalizedError {
                                Text(error.errorDescription ?? error.localizedDescription)
                            } else {
                                Text(error.localizedDescription)
                            }
                            Button {
                                fileState.excalidrawCollaborationWebCoordinator?.refresh()
                            } label: {
                                Text("Reload")
                                    .padding(.horizontal)
                            }
                            .controlSize(.large)
                            .buttonStyle(.borderedProminent)
                        }
                    }

            } else if isProgressViewPresented, canShowLoadingOverlay {
                loadingOverlayBackground

                VStack {
                    ProgressView()
                        .progressViewStyle(.circular)
                    Text(.localizable(.webViewLoadingText))
                }
            }
        }
        .overlay(alignment: .top) {
            if isRoomSyncNoticePresented {
                collaborationRoomSyncNotice
                    .padding(.top, collaborationRoomSyncNoticeTopPadding)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.smooth(duration: 0.25), value: isRoomSyncNoticePresented)
        .opacity(isActive ? 1 : 0)
        .watch(value: isActive) { active in
            guard active, loadingState == .loaded else { return }
            showRoomSyncNoticeIfNeeded()
        }
        .task {
            loadingOverlayCoverImage = loadingCoverImage
            do {
                // Load content from CollaborationFile
                let content = try await file.loadContent()
                var excalidrawFile = try ExcalidrawFile(data: content, id: file.id?.uuidString)
                excalidrawFile.roomID = file.roomID
                try await excalidrawFile.syncFiles(context: viewContext)
                await MainActor.run {
                    self.loadedContent = excalidrawFile.content ?? content
                    self.loadedRoomID = excalidrawFile.roomID
                    self.excalidrawFile = excalidrawFile
                }
            } catch {
                // Fallback to empty file if loading fails
                var excalidrawFile = ExcalidrawFile()
                excalidrawFile.id = file.id?.uuidString ?? UUID().uuidString
                excalidrawFile.roomID = file.roomID
                try? await excalidrawFile.syncFiles(context: viewContext)
                await MainActor.run {
                    self.loadedContent = excalidrawFile.content
                    self.loadedRoomID = excalidrawFile.roomID
                    self.excalidrawFile = excalidrawFile
                }
                alertToast(error)
            }
        }
        .onDisappear {
            fileState.collaboratingFilesState[file] = nil
            loadingOverlayCoverImage = nil
            roomSyncNoticeTask?.cancel()
            roomSyncNoticeTask = nil
            isRoomSyncNoticePresented = false
        }
    }

    private var collaborationRoomSyncNotice: some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.callout.weight(.semibold))
                .symbolRenderingMode(.hierarchical)

            VStack(alignment: .leading, spacing: 1) {
                Text(.localizable(.collaborationRoomSyncNoticeTitle))
                    .font(.callout)
                    .lineLimit(1)

                Text(.localizable(.collaborationRoomSyncNoticeSubtitle))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .foregroundStyle(.primary)
        .padding(.horizontal, 16)
        .frame(height: 52)
        .background {
            if #available(macOS 26.0, iOS 26.0, *) {
                Capsule()
                    .fill(.clear)
                    .glassEffect(.regular, in: Capsule())
            } else {
                Capsule()
                    .fill(.ultraThinMaterial)
            }
        }
        .overlay {
            Capsule()
                .stroke(.primary.opacity(0.08), lineWidth: 0.5)
        }
        .shadow(color: .black.opacity(0.12), radius: 16, y: 8)
    }

    private var collaborationRoomSyncNoticeTopPadding: CGFloat {
#if os(iOS)
        104
#else
        72
#endif
    }

    private var canShowCanvasContent: Bool {
        !fileHomeItemTransitionState.canShowItemContainerView
    }

    private var canShowLoadingOverlay: Bool {
        canShowCanvasContent
    }

    @ViewBuilder
    private var loadingOverlayBackground: some View {
        GeometryReader { geometry in
            let rect = adjustedLoadingOverlayBackgroundRect(in: geometry)

            loadingOverlayBackgroundContent
                .frame(width: rect.width, height: rect.height)
                .clipped()
                .offset(x: rect.minX, y: rect.minY)
        }
    }

    @ViewBuilder
    private var loadingOverlayBackgroundContent: some View {
        if let image = effectiveLoadingOverlayCoverImage {
            Image(platformImage: image)
                .resizable()
                .scaledToFill()
        } else {
            fallbackLoadingOverlayBackground
        }
    }

    private func adjustedLoadingOverlayBackgroundRect(in geometry: GeometryProxy) -> CGRect {
        let rect = CGRect(origin: .zero, size: geometry.size)
#if os(macOS)
        let topInset = max(
            geometry.safeAreaInsets.top,
            geometry.frame(in: .global).minY
        )
        guard topInset > 0 else { return rect }
        return CGRect(
            x: rect.minX,
            y: rect.minY - topInset,
            width: rect.width,
            height: rect.height + topInset
        )
#elseif os(iOS)
        return FileHomeCoverTransitionGeometry.rectClosestToImageAspect(
            rect,
            alternate: FileHomeCoverTransitionGeometry.rectIncludingIgnoredSafeArea(
                rect,
                in: geometry
            ),
            image: effectiveLoadingOverlayCoverImage
        )
#else
        return rect
#endif
    }

    private var effectiveLoadingOverlayCoverImage: PlatformImage? {
        loadingOverlayCoverImage ?? loadingCoverImage
    }

    private var loadingCoverImage: PlatformImage? {
        guard let fileID = file.id?.uuidString else { return nil }
        return FileItemPreviewCache.shared.getPreviewCache(
            forID: fileID,
            colorScheme: colorScheme
        )
    }

    @ViewBuilder
    private var fallbackLoadingOverlayBackground: some View {
        if #available(macOS 14.0, iOS 17.0, *) {
            Rectangle()
                .fill(.windowBackground)
        } else {
            Rectangle()
                .fill(Color.windowBackgroundColor)
        }
    }

    private func showRoomSyncNoticeIfNeeded() {
        guard isActive,
              !didShowRoomSyncNotice,
              file.roomID?.isEmpty == false else {
            return
        }

        didShowRoomSyncNotice = true
        roomSyncNoticeTask?.cancel()
        roomSyncNoticeTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard !Task.isCancelled else { return }
            isRoomSyncNoticePresented = true
            try? await Task.sleep(nanoseconds: 10_000_000_000)
            guard !Task.isCancelled else { return }
            isRoomSyncNoticePresented = false
            roomSyncNoticeTask = nil
        }
    }
}
