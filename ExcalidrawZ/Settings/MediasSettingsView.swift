//
//  MediasSettingsView.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 2024/11/15.
//

import SwiftUI
import ChocofordUI

struct MediasSettingsView: View {
    @Environment(\.containerHorizontalSizeClass) private var containerHorizontalSizeClass
    @Environment(\.containerVerticalSizeClass) private var containerVerticalSizeClass
    @FetchRequest(sortDescriptors: [SortDescriptor(\MediaItem.createdAt, order: .reverse)])
    private var medias: FetchedResults<MediaItem>
    
    @State private var selection: MediaItem?
    @State private var loadedDataURL: String?
    
    var body: some View {
        if containerHorizontalSizeClass == .compact, containerVerticalSizeClass == .regular {
            horizontalCompactContent()
        } else {
#if os(iOS)
            galleryView()
//            if #available(iOS 18.0, *) {
//                regularContent()
//                    .toolbarVisibility(.visible, for: .navigationBar)
//            } else {
//                regularContent()
//                    .toolbar(.visible, for: .navigationBar)
//            }
#elseif os(macOS)
            regularContent()
#endif
        }
    }
    
    
    @MainActor @ViewBuilder
    private func regularContent() -> some View {
        HStack {
            mediaList()
                .frame(width: 200)
            
            Divider()
            
            detailView()
                .padding()
                .frame(maxWidth: .infinity)
                .task(id: selection?.objectID) {
                    if let selection = selection {
                        loadedDataURL = try? await selection.loadDataURL()
                    } else {
                        loadedDataURL = nil
                    }
                }
        }
    }
    
    @MainActor @ViewBuilder
    private func horizontalCompactContent() -> some View {
        VStack {
            detailView()
                .padding()
                .frame(maxWidth: .infinity)
                .frame(height: 300)
                .task(id: selection?.objectID) {
                    if let selection = selection {
                        loadedDataURL = try? await selection.loadDataURL()
                    } else {
                        loadedDataURL = nil
                    }
                }
            mediaList()
#if os(macOS)
                .visualEffect(material: .sidebar)
#elseif os(iOS)
                .background {
                    if #available(macOS 14.0, iOS 17.0, *) {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(.regularMaterial)
                            .stroke(.separator, lineWidth: 0.5)
                    } else {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(.regularMaterial)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal)
#endif
        }
    }
    
    @MainActor @ViewBuilder
    private func mediaList() -> some View {
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
    }
    
    @MainActor @ViewBuilder
    private func detailView() -> some View {
        ZStack {
            if let item = selection,
               let imageDataString = loadedDataURL?.components(separatedBy: "base64,").last,
               let imageData = Data(base64Encoded: imageDataString) {
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
                                Text("Copy")
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
    }
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
                let dataURLString = try? await item.loadDataURL()
                if let imageDataString = dataURLString?.components(separatedBy: "base64,").last,
                   let imageData = Data(base64Encoded: imageDataString) {
                    await MainActor.run {
                        self.data = imageData
                    }
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
    
    var body: some View {
        ZStack {
            ThumbnailImage(
                platformImage, size: CGSize(width: 500, height: 500)
            ) { image in
                image
                    .resizable()
            } placeholder: {
                Rectangle()
                    .fill(.secondary)
            }
        }
        .watchImmediately(of: data) { newValue in
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
                }
            }
        }
    }
}


#Preview {
    MediasSettingsView()
}
