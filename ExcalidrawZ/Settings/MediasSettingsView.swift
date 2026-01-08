//
//  MediasSettingsView.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 2024/11/15.
//

import SwiftUI
import CoreData
import ChocofordUI

struct MediasSettingsView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.containerHorizontalSizeClass) private var containerHorizontalSizeClass
    @Environment(\.containerVerticalSizeClass) private var containerVerticalSizeClass
    @Environment(\.alertToast) private var alertToast
    @FetchRequest(sortDescriptors: [SortDescriptor(\MediaItem.createdAt, order: .reverse)])
    private var medias: FetchedResults<MediaItem>

    @State private var selection: MediaItem?
    @State private var loadedData: Data?
    @State private var isCleaningOrphans = false
    @State private var isCleanupAlertPresented = false
    @State private var cleanupResult: CleanupResult?
    
    var body: some View {
        content()
            
    }
    
    @ViewBuilder
    private func content() -> some View {
#if os(iOS)
        galleryView()
#elseif os(macOS)
        regularContent()
#endif
    }
    
    @MainActor @ViewBuilder
    private func regularContent() -> some View {
        HStack(spacing: 0) {
            mediaList()
                .frame(width: 200)

            Divider()

            detailView()
                .padding()
                .frame(maxWidth: .infinity)
                .task(id: selection?.objectID) {
                    if let selection = selection {
                        loadedData = try? await selection.loadData()
                    } else {
                        loadedData = nil
                    }
                }
        }
    }
    
    @MainActor @ViewBuilder
    private func mediaList() -> some View {
        VStack(spacing: 0) {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(medias, id: \.objectID) { item in
                        Button {
                            selection = item
                        } label: {
                            Text(item.id ?? String(localizable: .generalUnknown))
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        .buttonStyle(
                            .excalidrawSidebarRow(
                                isSelected: selection == item,
                                isMultiSelected: false
                            )
                        )
                    }
                }
                .padding(10)
                .frame(minHeight: 400, alignment: .top)
                .background {
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture {
                            selection = nil
                        }
                }
            }
            
            Divider()
            
            HStack {
                Spacer()
                cleanupOrphanMediasButton()
                    .buttonStyle(.borderless)
            }
            .padding(12)
        }
    }
    
    @MainActor @ViewBuilder
    private func detailView() -> some View {
        ZStack {
            if let item = selection,
               let imageData = loadedData {
                VStack {
                    DataImage(data: imageData)
                        .scaledToFit()
                        .frame(maxHeight: .infinity)
                        .contextMenu {
                            Button {
#if canImport(AppKit)
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setData(imageData, forType: .png)
#elseif canImport(UIKit)
                                if let image = UIImage(data: imageData) {
                                    UIPasteboard.general.setObjects([image])
                                }
#endif
                            } label: {
                                Text(localizable: .generalButtonCopy)
                            }
                        }

                    VStack(alignment: .leading) {
                        Text(item.id ?? String(localizable: .generalUntitled))
                            .font(.headline)
                        HStack {
                            VStack(alignment: .trailing) {
                                Text("\(String(localizable: .mediasInfoLabelCreatedAt)):")
                                Text("\(String(localizable: .mediasInfoLabelFileSize)):")
                                Text("\(String(localizable: .mediasInfoLabelReferencedFrom)):")
                            }
                            VStack(alignment: .leading) {
                                Text((item.createdAt ?? .distantPast).formatted())
                                Text(imageData.count.formatted(.byteCount(style: .file)))
                                Text(item.file?.name ?? String(localizable: .generalUnknown))
                            }
                            .foregroundStyle(.secondary)
                        }
                    }
                    .lineLimit(1)
                    .padding(20)
                    .frame(maxWidth: .infinity)
                    .background {
                        ZStack {
                            let roundedRectangle = RoundedRectangle(cornerRadius: 8)
                            roundedRectangle.fill(.regularMaterial)
                            if #available(macOS 13.0, iOS 17.0, *) {
                                roundedRectangle.stroke(.separator)
                            } else {
                                roundedRectangle.stroke(.secondary)
                            }
                        }
                    }
#if os(macOS)
                    .padding(.horizontal, 100)
#elseif os(iOS)
                    .padding(.horizontal, 20)
#endif
                }
            } else {
                placeholderView()
            }
        }
    }
    
    @MainActor @ViewBuilder
    private func placeholderView() -> some View {
        VStack {
            Text(.localizable(.settingsMediasName)).font(.largeTitle)
            VStack(alignment: .leading) {
                Text(.localizable(.settingsMediasDescription))
            }
            .padding()
            .background {
                let roundedRectangle = RoundedRectangle(cornerRadius: 8)
                ZStack {
                    roundedRectangle.fill(.regularMaterial)
                    if #available(macOS 13.0, iOS 17.0, *) {
                        roundedRectangle.stroke(.separator)
                    } else {
                        roundedRectangle.stroke(.secondary)
                    }
                }
            }
        }
        .frame(maxWidth: 400)
    }
    
    @MainActor @ViewBuilder
    private func galleryView() -> some View {
        ScrollView {
            LazyVGrid(columns: [.init(.adaptive(minimum: 120, maximum: 300))]) {
                ForEach(medias, id: \.objectID) { item in
                    MediaItemImageView(item: item)
                        .aspectRatio(1, contentMode: .fill)
                }
            }
        }
#if os(iOS)
        .toolbar {
            cleanupOrphanMediasButton()
        }
#endif
    }

    // MARK: - Cleanup Methods

    @ViewBuilder
    private func cleanupOrphanMediasButton() -> some View {
        Button {
            isCleanupAlertPresented = true
        } label: {
            Label(.localizable(.settingsMediaFilesButtonCleanUp), systemSymbol: .trash)
                .labelStyle(.iconOnly)
        }
        .disabled(isCleaningOrphans)
        .help(.localizable(.settingsMediaFilesButtonHelpCleanUp))
        .confirmationDialog(
            String(localizable: .settingsMediaFilesCleanUpConfirmationDialogTitle),
            isPresented: $isCleanupAlertPresented
        ) {
            Button(.localizable(.settingsMediaFilesButtonCleanUp), role: .destructive) {
                Task {
                    await cleanupOrphanMedias()
                }
            }
            Button(.localizable(.generalButtonCancel), role: .cancel) {}
        } message: {
            Text(localizable: .settingsMediaFilesCleanUpConfirmationDialogMessage)
        }
    }

    private func cleanupOrphanMedias() async {
        isCleaningOrphans = true
        defer { isCleaningOrphans = false }

        do {
            let result = try await performCleanupOrphanMedias(context: viewContext)
            await MainActor.run {
                self.cleanupResult = result
                alertToast(
                    .init(
                        displayMode: .hud,
                        type: .complete(.green),
                        title: String(localizable: .generalSuccess),
                        subTitle: "Removed \(result.deletedCount) orphaned media items.",
                    )
                )
            }
        } catch {
            await MainActor.run {
                alertToast(error)
            }
        }
    }

    /// Find and delete MediaItems that are no longer referenced by any File or FileCheckpoint
    private func performCleanupOrphanMedias(context: NSManagedObjectContext) async throws -> CleanupResult {
        return try await context.perform {
            let fetchRequest: NSFetchRequest<MediaItem> = MediaItem.fetchRequest()
            let allMediaItems = try context.fetch(fetchRequest)

            var deletedCount = 0
            var recoveredSpace: Int64 = 0

            for mediaItem in allMediaItems {
                // Check if the referenced file exists
                if let file = mediaItem.file {
                    // File reference exists, check if file is deleted
                    if file.isDeleted {
                        // File is deleted, this media is orphaned
                        if let dataURL = mediaItem.dataURL,
                           let base64String = dataURL.components(separatedBy: "base64,").last,
                           let data = Data(base64Encoded: base64String) {
                            recoveredSpace += Int64(data.count)
                        }
                        context.delete(mediaItem)
                        deletedCount += 1
                    }
                } else {
                    // No file reference, this media is orphaned
                    if let dataURL = mediaItem.dataURL,
                       let base64String = dataURL.components(separatedBy: "base64,").last,
                       let data = Data(base64Encoded: base64String) {
                        recoveredSpace += Int64(data.count)
                    }
                    context.delete(mediaItem)
                    deletedCount += 1
                }
            }

            if deletedCount > 0 {
                try context.save()
            }

            return CleanupResult(deletedCount: deletedCount, recoveredSpace: recoveredSpace)
        }
    }
}

// MARK: - Supporting Types

struct CleanupResult {
    let deletedCount: Int
    let recoveredSpace: Int64
}

struct MediaItemImageView: View {
    var item: MediaItem
    
    @State private var data: Data? = nil
    
    var body: some View {
        Color.clear
            .overlay {
                if let data {
                    DataImage(data: data)
                        .scaledToFit()
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .task {
                // Load raw data directly from FileStorage (local/iCloud) or CoreData
                let imageData = try? await item.loadData()
                await MainActor.run {
                    self.data = imageData
                }
            }
    }
}

struct DataImage: View {
    var data: Data
    
    init(data: Data) {
        self.data = data
    }
    
    @State private var image: Image?
#if canImport(AppKit)
    @State private var platformImage: NSImage?
#elseif canImport(UIKit)
    @State private var platformImage: UIImage?
#endif
    
    @State private var viewID: UUID = UUID()
    
    var body: some View {
        ZStack {
            ThumbnailImage(
                platformImage,
                width: 300,
            ) { image in
                image
                    .resizable()
            } placeholder: {
                Rectangle()
                    .fill(.secondary.opacity(0.4))
            }
            .id(viewID)
        }
        .watch(value: data) { newValue in
            Task.detached {
                let image = Image(data: newValue)
#if canImport(AppKit)
                let platformImage = NSImage(data: newValue)
#elseif canImport(UIKit)
                let platformImage = UIImage(data: newValue)
#endif
                await MainActor.run {
                    self.platformImage = platformImage
                    self.image = image
                    viewID = UUID()
                }
            }
        }
    }
}


#Preview {
    MediasSettingsView()
}
