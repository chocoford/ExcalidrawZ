//
//  ExportFileView.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 2023/8/8.
//

import SwiftUI
import ChocofordUI
import ComposableArchitecture
import UniformTypeIdentifiers

struct ExportFileStore: ReducerProtocol {
    struct State: Equatable, Hashable {
        var file: File
        
        var url: URL? = nil
    }
    
    enum Action: Equatable {
        case setURL(URL)
        
        case dismiss
        
        case setError(AppError)
    }
    
    @Dependency(\.dismiss) var dismiss
    @Dependency(\.errorBus) var errorBus
    
    var body: some ReducerProtocol<State, Action> {
        Reduce { state, action in
            switch action {
                case .setURL(let url):
                    state.url = url
                    return .none
                    
                case .dismiss:
                    return .run { send in
                        await dismiss()
                    }
                    
                case .setError(let error):
                    errorBus.submit(error)
                    return .none
            }
        }
    }
}

@available(macOS 13.0, *)
struct ExcalidrawFileDocument: Transferable {
    var file: File
    
    init(file: File) {
        self.file = file
    }
    
    func fileURL() -> Data {
        do {
            let fileManager: FileManager = FileManager.default
            let directory: URL = try fileManager.url(
                for: .itemReplacementDirectory,
                in: .userDomainMask,
                appropriateFor: .applicationSupportDirectory,
                create: true
            )
            
            let fileExtension = "excalidraw"
            
            let filename = (file.name ?? "Untitled") + ".\(fileExtension)"
            let url = directory.appendingPathComponent(filename, conformingTo: .fileURL)
            if fileManager.fileExists(atPath: url.absoluteString) {
                try fileManager.removeItem(at: url)
            }
            fileManager.createFile(atPath: url.path(), contents: file.content)
            return url.dataRepresentation
        } catch {
            return Data()
        }
    }
    
    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .fileURL) { file in
            file.fileURL()
        }
    }
}

struct ExportFileView: View {
    let store: StoreOf<ExportFileStore>
    
    @State private var loadingImage: Bool = false
    @State private var showFileExporter = false
    @State private var showShare: Bool = false
    @State private var fileName: String = ""
    @State private var copied: Bool = false
    
    @State private var fileContentString: String = ""
    
    var body: some View {
        WithViewStore(self.store, observe: {$0}) { viewStore in
            Center {
                if #available(macOS 13.0, *) {
                    Image(systemName: "doc.text")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(height: 80)
                        .draggable(ExcalidrawFileDocument(file: viewStore.file))
                        .padding()
                } else {
                    Image(systemName: "doc.text")
                        .padding()
                }
                
                TextField("", text: $fileName)
                    .textFieldStyle(.roundedBorder)
                    .onAppear {
                        fileName = viewStore.file.name ?? "Untitled"
                    }
                    .frame(width: 260)
                actionsView()
            }
            .onAppear {
                saveFileToTemp()
            }
        }
    }
    
    @ViewBuilder
    private func actionsView() -> some View {
        WithViewStore(self.store, observe: {$0}) { viewStore in
            HStack {
                Spacer()
                Button {
                    NSPasteboard.general.clearContents()
                    if let url = viewStore.url,
                       let url = (url as NSURL).fileReferenceURL() as NSURL? {
                        NSPasteboard.general.writeObjects([url])
                        NSPasteboard.general.setString(url.relativeString, forType: .fileURL)
                        NSPasteboard.general.setData(viewStore.file.content, forType: .fileContents)
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
                
                if #available(macOS 13.0, *),
                    let url = viewStore.url {
                    ShareLink("Share", item: url)
                } else {
                    Button {
                        self.showShare = true
                    } label: {
                        Label("Share", systemImage: "square.and.arrow.up")
                            .padding(.horizontal, 6)
                    }
                    .background(SharingsPicker(
                        isPresented: $showShare,
                        sharingItems: viewStore.url != nil ? [viewStore.url!] : []
                    ))
                }
                
                Spacer()
            }
            .fileExporter(isPresented: $showFileExporter,
                          document: TextFile(viewStore.file.content),
                          contentType: .text,
                          defaultFilename: fileName,
                          onCompletion: { result in
                switch result {
                    case .success:
                        self.store.send(.dismiss)
                    case .failure(let failure):
                        self.store.send(.setError(.unexpected(.init(failure))))
                }
            })
        }
    }
    
    
    func saveFileToTemp() {
        self.store.withState { state in
            // save file to temp folder
            do {
                let fileManager: FileManager = FileManager.default
                guard let directory: URL = try getTempDirectory() else { return }
                let fileExtension = "excalidraw"
                let filename = (state.file.name ?? "Untitled") + ".\(fileExtension)"
                let url = directory.appendingPathComponent(filename, conformingTo: .fileURL)
                if fileManager.fileExists(atPath: url.absoluteString) {
                    try fileManager.removeItem(at: url)
                }
                if #available(macOS 13.0, *) {
                    fileManager.createFile(atPath: url.path(percentEncoded: false), contents: state.file.content)
                } else {
                    fileManager.createFile(atPath: url.path, contents: state.file.content)
                }
                self.store.send(.setURL(url))
                
            } catch {
                self.store.send(.setError(.init(error)))
            }
        }
        
    }
}

struct TextFile: FileDocument {
    enum TextFileError: Error {
        case initFailed
        case makeFileWrapperFailed
    }
    
    static var readableContentTypes = [UTType.text]

    // by default our document is empty
    var data: Data?
    
    init(_ data: Data?) {
        self.data = data
    }
    
    // this initializer loads data that has been saved previously
    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw TextFileError.initFailed
        }
        self.data = data
    }

    // this will be called when the system wants to write our data to disk
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        guard let data = self.data else { throw TextFileError.makeFileWrapperFailed }
        let fileWrapper = FileWrapper(regularFileWithContents: data)
        return fileWrapper
    }
}

#if DEBUG
#Preview {
    ExportFileView(
        store: .init(initialState: .init(file: .preview)) {
            ExportFileStore()
        }
    )
}
#endif
