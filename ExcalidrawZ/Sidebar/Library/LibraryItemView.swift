//
//  LibraryItemView.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 2024/9/2.
//

import SwiftUI

import ChocofordUI

//struct ExcalidrawElementsTranferable: Transferable {
//    var elements: [ExcalidrawElement]
//    
//    static var transferRepresentation: some TransferRepresentation {
//        
//    }
//}


struct LibraryItemView: View {
    @Environment(\.colorScheme) var colorScheme
    
    @EnvironmentObject var exportState: ExportState
    
    var item: ExcalidrawLibrary
    @State private var image: Image?

    var body: some View {
        ZStack {
            if colorScheme == .light {
                content()
            } else {
                content()
                    .colorInvert()
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .font(.footnote)
        .lineLimit(1)
        .truncationMode(.middle)
        .onDrag {
            let itemProvider = NSItemProvider()
            itemProvider.registerDataRepresentation(
                forTypeIdentifier: "com.chocoford.excalidrawlibJSON",
                visibility: .all
            ) { completion in
                do {
                    let data = try item.jsonStringified().data(using: .utf8)
                    completion(data, nil)
                } catch {
                    print(error)
                    completion(nil, error)
                }
                return Progress(totalUnitCount: 100)
            }
            
            return itemProvider
        }
        .onAppear {
            guard let webCoordinator = exportState.excalidrawWebCoordinator else { return }
            Task.detached {
                do {
                    let nsImage = try await webCoordinator.exportElementsToPNG(
                        id: item.libraryItems[0].id,
                        elements: item.libraryItems[0].elements
                    )
                    let image = Image(nsImage: nsImage)
                    await MainActor.run {
                        self.image = image
                    }
                } catch {
                    dump(error)
                }
            }
        }
    }
    
    @MainActor @ViewBuilder
    private func content() -> some View {
        Center {
            VStack {
                if let image {
                    image
                        .resizable()
                        .scaledToFit()
                } else {
                    Color.clear
                }
            }
        }
        .frame(height: 80)
        .background(.white)
    }
}
