#if os(macOS)
import AppKit
import Combine
import CoreData
import Foundation
import UniformTypeIdentifiers

enum ScreenAnnotationSaveDestination: Hashable {
    case newFile
    case clipboard
    case downloads
    case customLocation
    case libraryFile(objectID: NSManagedObjectID, name: String)
    case localFile(url: URL)

    var title: String {
        switch self {
            case .newFile:
                "New Excalidraw File"
            case .clipboard:
                "Clipboard"
            case .downloads:
                "Downloads"
            case .customLocation:
                "Custom Location"
            case .libraryFile(_, let name):
                name
            case .localFile(let url):
                url.deletingPathExtension().lastPathComponent
        }
    }

    var isExcalidrawFile: Bool {
        switch self {
            case .newFile, .libraryFile, .localFile:
                true
            case .clipboard, .downloads, .customLocation:
                false
        }
    }
}

enum ScreenAnnotationSaveFormat: String, CaseIterable, Hashable {
    case raw
    case png
    case jpeg

    var title: String {
        switch self {
            case .raw:
                "Raw"
            case .png:
                "PNG"
            case .jpeg:
                "JPEG"
        }
    }

    var fileExtension: String {
        switch self {
            case .raw:
                "excalidraw"
            case .png:
                "png"
            case .jpeg:
                "jpg"
        }
    }

    var mimeType: String {
        switch self {
            case .raw:
                "application/vnd.excalidraw+json"
            case .png, .jpeg:
                "image/\(rawValue)"
        }
    }

    var contentType: UTType {
        switch self {
            case .raw:
                .excalidrawFile
            case .png:
                .png
            case .jpeg:
                .jpeg
        }
    }

    var bitmapFileType: NSBitmapImageRep.FileType {
        switch self {
            case .raw:
                .png
            case .png:
                .png
            case .jpeg:
                .jpeg
        }
    }

    var bitmapProperties: [NSBitmapImageRep.PropertyKey: Any] {
        switch self {
            case .raw, .png:
                [:]
            case .jpeg:
                [.compressionFactor: 0.92]
        }
    }
}

@MainActor
final class ScreenAnnotationSaveConfiguration: ObservableObject {
    @Published private(set) var destination: ScreenAnnotationSaveDestination
    @Published private(set) var fileDestination: ScreenAnnotationSaveDestination
    @Published var format: ScreenAnnotationSaveFormat

    init(
        destination: ScreenAnnotationSaveDestination = .newFile,
        format: ScreenAnnotationSaveFormat = .raw
    ) {
        self.destination = destination
        self.fileDestination = destination.isExcalidrawFile
            ? destination
            : .newFile
        self.format = format
    }

    var title: String {
        destination.title
    }

    var availableFormats: [ScreenAnnotationSaveFormat] {
        destination.isExcalidrawFile
            ? [.raw]
            : ScreenAnnotationSaveFormat.allCases
    }

    func selectDestination(_ destination: ScreenAnnotationSaveDestination) {
        self.destination = destination
        if destination.isExcalidrawFile {
            fileDestination = destination
            format = .raw
        }
    }

    func selectFileDestination(
        _ destination: ScreenAnnotationSaveDestination
    ) {
        guard destination.isExcalidrawFile else { return }
        fileDestination = destination
        self.destination = destination
        format = .raw
    }
}
#endif
