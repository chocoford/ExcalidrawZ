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
    @FetchRequest(sortDescriptors: [SortDescriptor(\MediaItem.createdAt, order: .reverse)])
    private var medias: FetchedResults<MediaItem>

    @State private var selectedMediaID: NSManagedObjectID?
    @State private var isCleanupSheetPresented = false

    var body: some View {
        content()
            .sheet(isPresented: $isCleanupSheetPresented) {
                MediaCleanupSheet()
            }
    }

    @ViewBuilder
    private func content() -> some View {
#if os(iOS)
        NavigationStack {
            galleryView()
                .navigationTitle(.localizable(.settingsMediasName))
                .navigationDestination(for: MediaRoute.self) { route in
                    MediaSettingsDestinationView(route: route)
                }
        }
#elseif os(macOS)
        regularContent()
            .navigationTitle(.localizable(.settingsMediasName))
#endif
    }

#if os(macOS)
    @ViewBuilder
    private func regularContent() -> some View {
        if #available(macOS 14.0, *) {
            galleryView()
                .inspector(isPresented: isMediaInspectorPresented) {
                    if let selectedMedia {
                        detailPanelContent(item: selectedMedia)
                            .inspectorColumnWidth(min: 280, ideal: 320, max: 380)
                    }
                }
        } else {
            floatingDetailContent()
        }
    }

    private var isMediaInspectorPresented: Binding<Bool> {
        Binding {
            selectedMedia != nil
        } set: { isPresented in
            if !isPresented {
                selectedMediaID = nil
            }
        }
    }

    private func floatingDetailContent() -> some View {
        ZStack(alignment: .trailing) {
            galleryView()

            if let selectedMedia {
                floatingDetailPanel(item: selectedMedia)
                    .frame(width: 320)
                    .padding(10)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                    .zIndex(1)
            }
        }
        .animation(.smooth(duration: 0.25), value: selectedMediaID)
    }

    private var selectedMedia: MediaItem? {
        guard let selectedMediaID else { return nil }
        return medias.first { $0.objectID == selectedMediaID }
    }

    private func floatingDetailPanel(item: MediaItem) -> some View {
        detailPanelContent(item: item)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .background {
                let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
                if #available(macOS 26.0, *) {
                    shape
                        .fill(.background)
                        .glassEffect(.regular, in: shape)
                        .shadow(radius: 4)
                } else {
                    shape
                        .fill(.regularMaterial)
                        .shadow(radius: 4)
                }
            }
    }

    private func detailPanelContent(item: MediaItem) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text(item.file?.name ?? item.collaborationFile?.name ?? String(localizable: .settingsMediasName))
                    .font(.headline)
                    .lineLimit(1)

                Spacer(minLength: 0)

                Button {
                    selectedMediaID = nil
                } label: {
                    Image(systemSymbol: .xmark)
                }
                .modernButtonStyle(style: .glass, size: .small, shape: .circle)
            }
            .padding(12)

            Divider()

            MediaItemDetailContent(item: item)
        }
    }
#endif

    @ViewBuilder
    private func galleryView() -> some View {
        ZStack {
            if medias.isEmpty {
                VStack(spacing: 10) {
                    Image(systemSymbol: .photoOnRectangle)
                        .font(.system(size: 36))
                        .foregroundStyle(.secondary)
                    Text(localizable: .settingsMediasDescription)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 360)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
            } else {
                ScrollView {
                    LazyVGrid(columns: gridColumns, spacing: 8) {
                        ForEach(medias, id: \.objectID) { item in
#if os(iOS)
                            NavigationLink(value: MediaRoute.mediaItem(item.objectID)) {
                                MediaItemGridCell(item: item, isSelected: false)
                            }
                            .buttonStyle(.plain)
#elseif os(macOS)
                            Button {
                                selectedMediaID = selectedMediaID == item.objectID ? nil : item.objectID
                            } label: {
                                MediaItemGridCell(
                                    item: item,
                                    isSelected: selectedMediaID == item.objectID
                                )
                            }
                            .buttonStyle(.plain)
#endif
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    .padding(.bottom, 72)
                }
            }
        }
        .overlay(alignment: .bottomLeading) {
            if !medias.isEmpty {
                cleanupMediaButton()
                    .padding(16)
            }
        }
    }

    private var gridColumns: [GridItem] {
#if os(macOS)
        [GridItem(.adaptive(minimum: 150, maximum: 220), spacing: 8)]
#else
        [GridItem(.adaptive(minimum: 120, maximum: 200), spacing: 8)]
#endif
    }

    @ViewBuilder
    private func cleanupMediaButton() -> some View {
        Button {
            isCleanupSheetPresented = true
        } label: {
            Label(.localizable(.settingsMediaFilesButtonCleanUp), systemSymbol: .trash)
        }
        .modernButtonStyle(style: .glass, size: .regular, shape: .capsule)
        .help(.localizable(.settingsMediaFilesButtonHelpCleanUp))
    }
}

#Preview {
    MediasSettingsView()
}
