//
//  ExportImageView.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 2023/4/3.
//

import Foundation
import SwiftUI
import ChocofordUI
import UniformTypeIdentifiers
import WebKit

struct ExportImageView: View {
    @EnvironmentObject var store: AppStore
    @Binding var isPresent: Bool
    var exportState: ExportState?
    
    @State private var image: NSImage? = nil
    @State private var loadingImage: Bool = false
    @State private var showFileExporter = false
    @State private var showShare: Bool = false
    @State private var fileName: String = ""
    @State private var copied: Bool = false
    
    
    var body: some View {
        VStack {
            HStack {
                Text("Export image...")
                    .font(.title)
                Spacer()
                
                Button {
                    exportState?.download?.cancel()
                    isPresent = false
                } label: {
                    Image(systemName: "xmark")
                        .padding(8)
                }
                .buttonStyle(.borderless)
            }
            Divider()
            Spacer(minLength: 0)
            content
            Spacer(minLength: 0)
        }
        .onAppear {
        }
        .onChange(of: exportState?.url, perform: { newValue in
            if let url = newValue {
                loadingImage = true
                DispatchQueue.global().async {
                    let image = NSImage(contentsOf: url)?.resizeWhileMaintainingAspectRatioToSize(size: .init(width: 200, height: 100))
                    DispatchQueue.main.async {
                        self.image = image
                        loadingImage = false
                    }
                }
            }
            if let component = newValue?.lastPathComponent {
                fileName = component
            }
        })
        .onDisappear {
            if let url = exportState?.url {
                try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
            }
        }
        .padding()
        .frame(width: 400, height: 300, alignment: .center)
    }
    
    @ViewBuilder
    private var content: some View {
        if let url = exportState?.url, let image = image {
            VStack {
                thumbnailView(image, url: url)
                fileInfoView
                actionsView(url)
            }
        } else if exportState?.done == false || loadingImage {
            VStack {
                LoadingView(strokeColor: Color.accentColor)
                
                Text("Loading...")
                
                Button {
                    exportState?.download?.cancel()
                    isPresent = false
                } label: {
                    Text("Cancel")
                }
                .offset(y: 40)
            }
            
        } else {
            Text("Path not found.")
                .foregroundColor(.red)
                .italic()
        }
    }
    
    
    @ViewBuilder private func thumbnailView(_ image: NSImage, url: URL) -> some View {
        DragableImageView(image: image,
                          sourceURL: url)
        .frame(width: 200, height: 120, alignment: .center)
    }
    @ViewBuilder private var fileInfoView: some View {
        // File name
        TextField("", text: $fileName)
            .padding(.horizontal, 48)
    }
    @ViewBuilder
    private func actionsView(_ url: URL) -> some View {
        HStack {
            Spacer()
            Button {
                if let image = NSImage(contentsOf: url) {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.writeObjects([image])
                    withAnimation {
                        copied = true
                    }
                    Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { _ in
                        withAnimation {
                            copied = false
                        }
                    }
                }
            } label: {
                if copied {
                    Label("Copied", systemImage: "checkmark")
                        .padding(.horizontal, 6)
                } else {
                    Label("Copy", systemImage: "clipboard")
                        .padding(.horizontal, 6)
                }
            }
            .disabled(copied)
            
            Button {
                showFileExporter = true
            } label: {
                Label("Save", systemImage: "square.and.arrow.down")
                    .padding(.horizontal, 6)
            }
            
            Button {
                self.showShare = true
            } label: {
                Label("Share", systemImage: "square.and.arrow.up")
                    .padding(.horizontal, 6)
            }
            .background(SharingsPicker(isPresented: $showShare,
                                       sharingItems: [url]))
            
            Spacer()
        }
        .fileExporter(isPresented: $showFileExporter,
                      document: ImageFile(url),
                      contentType: .image,
                      defaultFilename: fileName,
                      onCompletion: { result in
            switch result {
                case .success(let success):
                    print(success)
                case .failure(let failure):
                    store.send(.setError(.fileError(.unexpected(failure))))
            }
            isPresent = false
        })
        .padding()
    }
}

struct ImageFile: FileDocument {
    enum ImageFileError: Error {
        case initFailed
        case makeFileWrapperFailed
    }
    
    static var readableContentTypes = [UTType.image]

    // by default our document is empty
    var url: URL

    init(_ url: URL) {
        self.url = url
    }
    
    // this initializer loads data that has been saved previously
    init(configuration: ReadConfiguration) throws {
        
//        if let data = configuration.file.regularFileContents, let img = NSImage(data: data) {
//            image = img
//        } else {
        throw ImageFileError.initFailed
//        }
    }

    // this will be called when the system wants to write our data to disk
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let fileWrapper = try FileWrapper(url: url)
//        fileWrapper.filename = fileName
//        fileWrapper.fileAttributes[FileAttributeKey.type.rawValue] = "png"
        return fileWrapper
    }
}

#if DEBUG
struct ExportImageView_Previews: PreviewProvider {
    static var previews: some View {
        ExportImageView(isPresent: .constant(true), exportState: nil)
            .environmentObject(AppStore.preview)
    }
}
#endif
