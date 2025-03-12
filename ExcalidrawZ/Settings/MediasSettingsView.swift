//
//  MediasSettingsView.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 2024/11/15.
//

import SwiftUI

struct MediasSettingsView: View {
    @Environment(\.containerHorizontalSizeClass) private var containerHorizontalSizeClass
    @Environment(\.containerVerticalSizeClass) private var containerVerticalSizeClass
    @FetchRequest(sortDescriptors: [SortDescriptor(\MediaItem.createdAt, order: .reverse)])
    private var medias: FetchedResults<MediaItem>
    
    @State private var selection: MediaItem?
    
    var body: some View {
        if containerHorizontalSizeClass == .compact, containerVerticalSizeClass == .regular {
            horizontalCompactContent()
        } else {
#if os(iOS)
            if #available(iOS 18.0, *) {
                regularContent()
                    .toolbarVisibility(.visible, for: .navigationBar)
            } else {
                regularContent()
                    .toolbar(.visible, for: .navigationBar)
            }
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
#if os(macOS)
                .visualEffect(material: .sidebar)
#elseif os(iOS)
                .background {
                    Rectangle()
                        .fill(.regularMaterial)
                        .border(.trailing, color: .separatorColor)
                }
#endif
            detailView()
                .padding()
                .frame(maxWidth: .infinity)
        }
    }
    
    @MainActor @ViewBuilder
    private func horizontalCompactContent() -> some View {
        VStack {
            detailView()
                .padding()
                .frame(maxWidth: .infinity)
                .frame(height: 300)
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
            LazyVStack {
                ForEach(medias, id: \.objectID) { item in
                    Button {
                        selection = item
                    } label: {
                        Text(item.id ?? String(localizable: .generalUnknown))
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    .buttonStyle(.listCell(selected: selection == item))
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
               let imageDataString = selection?.dataURL?.components(separatedBy: "base64,").last,
               let imageData = Data(base64Encoded: imageDataString) {
                VStack {
                    DataImage(data: imageData)
                        .scaledToFit()
                        .frame(maxHeight: .infinity)

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
    private func content() -> some View {
        
    }
}



struct DataImage: View {
    var data: Data
    
    init(data: Data) {
        self.data = data
    }
    
    @State private var image: Image?
    
    var body: some View {
        ZStack {
            if let image {
                image
                    .resizable()
            } else {
                Rectangle()
                    .fill(.secondary)
                    .shimmering()
            }
        }
        .watchImmediately(of: data) { newValue in
            Task.detached {
                let image = Image(data: newValue)
                await MainActor.run {
                    self.image = image
                }
            }
        }
    }
}

#Preview {
    MediasSettingsView()
}
