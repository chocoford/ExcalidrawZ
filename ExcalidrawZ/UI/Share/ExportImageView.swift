//
//  ExportImageView.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 2023/4/3.
//

import SwiftUI
import ChocofordUI
import UniformTypeIdentifiers
import WebKit
import ComposableArchitecture

struct ExportImageStore: ReducerProtocol {
    struct State: Equatable, Hashable {
        var url: URL?
        var download: WKDownload?
        var done: Bool = false
    }
    
    enum Action: Equatable {
        case setState(State)
        case setIsDone
        
        case dismiss
        case cancelExport
        
        case setError(_ error: FileError)
        
        case delegate(Delegate)
        
        enum Delegate: Equatable {
            case onAppear
        }
    }
    
    @Dependency(\.dismiss) var dismiss
    @Dependency(\.errorBus) var errorBus
    
    var body: some ReducerProtocol<State, Action> {
        Reduce { state, action in
            switch action {
                case .setState(let targetState):
                    state = targetState
                    return .none
                    
                case .setIsDone:
                    state.done = true
                    return .none
                    
                case .dismiss:
                    return .run { send in
                        await dismiss()
                    }
                case .cancelExport:
                    state.download?.cancel()
                    return .send(.dismiss)
                    
                case .setError(let error):
                    errorBus.submit(error)
                    return .none
                    
                case .delegate:
                    return .none
            }
        }
    }
}


struct ExportImageView: View {
    let store: StoreOf<ExportImageStore>
    
    @State private var image: NSImage? = nil
    @State private var loadingImage: Bool = false
    @State private var showFileExporter = false
    @State private var showShare: Bool = false
    @State private var fileName: String = ""
    @State private var copied: Bool = false
    @State private var hasError: Bool = false
    
    var body: some View {
        VStack {
            if #available(macOS 13.0, *) {} else {
                HStack {
                    Text("Export image...")
                        .font(.title)
                    Spacer()
                    
                    Button {
                        self.store.send(.dismiss)
                    } label: {
                        Image(systemName: "xmark")
                            .padding(8)
                    }
                    .buttonStyle(.borderless)
                }
                Divider()
            }
            Center {
                content
            }
        }
        .padding()
        .onAppear {
            self.store.send(.delegate(.onAppear))
        }
    }
    
    @ViewBuilder
    private var content: some View {
        WithViewStore(store, observe: {$0}) { store in
//            Text("Path not found.")
//                .foregroundColor(.red)
//                .italic()
            VStack {
                if let image = image, let url = store.state.url {
                    thumbnailView(image, url: url)
                    fileInfoView
                    actionsView(url)
                } else if hasError {
                    Text("Loading image failed.")
                        .foregroundColor(.red)
                } else {
                    ProgressView {
                    }
                    Text("Loading...")
                    
                    Button {
                        store.send(.cancelExport)
                        store.send(.dismiss)
                    } label: {
                        Text("Cancel")
                    }
                    .offset(y: 40)
                }
            }
            .watchImmediately(of: store.state.url) { url in
                guard let url = url else { return }
                DispatchQueue.main.asyncAfter(deadline: .now().advanced(by: .milliseconds(500))) {
                    guard let image = NSImage(contentsOf: url) else {
                        hasError = true
                        return
                    }
                    self.image = image.resizeWhileMaintainingAspectRatioToSize(size: .init(width: 200, height: 120))
                }
                fileName = url.lastPathComponent.components(separatedBy: ".").first ?? "Untitled"
            }
            .onDisappear {
                if let url = store.url {
                    try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
                }
                hasError = false
            }
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
            .textFieldStyle(.roundedBorder)
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
                    store.send(.setError(.unexpected(.init(failure))))
            }
            self.store.send(.dismiss)
        })
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
        ExportImageView(
            store: .init(initialState: .init(
                url: URL(string: "https://testres.trickle.so/upload/avatars/agents/fba0556877814fe6866c97f9813b6ad4_8f2a9057-681a-4a27-96ed-9d0c5696b941.png")!,
                download: .init()
            )) {
                ExportImageStore()
            }
        )
    }
}
#endif
