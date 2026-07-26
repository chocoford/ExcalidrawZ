#if os(macOS)
import AppKit
import Combine
import CoreData
import Foundation
import UniformTypeIdentifiers

enum ScreenAnnotationSaveDestination: Hashable {
    case newFile
    case clipboard
    case customLocation
    case libraryFile(objectID: NSManagedObjectID, name: String)
    case localFile(url: URL)

    var title: String {
        switch self {
            case .newFile:
                "New Excalidraw File"
            case .clipboard:
                "Clipboard"
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
            case .clipboard, .customLocation:
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
    private struct RecentFileReference: Codable, Hashable {
        enum Kind: String, Codable {
            case library
            case local
        }

        let kind: Kind
        let identifier: String
    }

    private static let recentFileDestinationsKey =
        "ScreenAnnotationRecentFileDestinations"
    private static let recentFileDestinationLimit = 5

    @Published private(set) var destination: ScreenAnnotationSaveDestination
    @Published private(set) var fileDestination: ScreenAnnotationSaveDestination
    @Published private(set) var recentFileDestinations:
        [ScreenAnnotationSaveDestination] = []
    @Published var format: ScreenAnnotationSaveFormat

    private var recentFileReferences: [RecentFileReference] = []

    init(
        destination: ScreenAnnotationSaveDestination = .newFile,
        format: ScreenAnnotationSaveFormat = .raw
    ) {
        self.destination = destination
        self.fileDestination = destination.isExcalidrawFile
            ? destination
            : .newFile
        self.format = format
        recentFileReferences = Self.loadRecentFileReferences()
        recentFileDestinations = Self.resolveDestinations(
            from: recentFileReferences
        )
    }

    var title: String {
        destination.title
    }

    var availableFormats: [ScreenAnnotationSaveFormat] {
        ScreenAnnotationSaveFormat.allCases
    }

    var fileDestinationOptions: [ScreenAnnotationSaveDestination] {
        var destinations: [ScreenAnnotationSaveDestination] = [.newFile]
        if fileDestination != .newFile,
           !recentFileDestinations.contains(fileDestination) {
            destinations.append(fileDestination)
        }
        destinations.append(contentsOf: recentFileDestinations)
        return destinations
    }

    func selectDestination(_ destination: ScreenAnnotationSaveDestination) {
        self.destination = destination
        if destination.isExcalidrawFile {
            fileDestination = destination
        }
    }

    func selectFileDestination(
        _ destination: ScreenAnnotationSaveDestination
    ) {
        guard destination.isExcalidrawFile else { return }
        fileDestination = destination
        self.destination = destination
    }

    func recordSuccessfulSave(
        to destination: ScreenAnnotationSaveDestination
    ) {
        guard let reference = Self.reference(for: destination) else {
            return
        }

        recentFileReferences.removeAll { $0 == reference }
        recentFileReferences.insert(reference, at: 0)
        recentFileReferences = Array(
            recentFileReferences.prefix(Self.recentFileDestinationLimit)
        )
        Self.saveRecentFileReferences(recentFileReferences)
        recentFileDestinations = Self.resolveDestinations(
            from: recentFileReferences
        )
    }

    private static func reference(
        for destination: ScreenAnnotationSaveDestination
    ) -> RecentFileReference? {
        switch destination {
            case .libraryFile(let objectID, _):
                return RecentFileReference(
                    kind: .library,
                    identifier: objectID.uriRepresentation().absoluteString
                )
            case .localFile(let url):
                return RecentFileReference(
                    kind: .local,
                    identifier: url.standardizedFileURL.absoluteString
                )
            case .newFile, .clipboard, .customLocation:
                return nil
        }
    }

    private static func loadRecentFileReferences() -> [RecentFileReference] {
        guard let data = UserDefaults.standard.data(
            forKey: recentFileDestinationsKey
        ) else {
            return []
        }
        return (try? JSONDecoder().decode(
            [RecentFileReference].self,
            from: data
        )) ?? []
    }

    private static func saveRecentFileReferences(
        _ references: [RecentFileReference]
    ) {
        guard let data = try? JSONEncoder().encode(references) else {
            return
        }
        UserDefaults.standard.set(
            data,
            forKey: recentFileDestinationsKey
        )
    }

    private static func resolveDestinations(
        from references: [RecentFileReference]
    ) -> [ScreenAnnotationSaveDestination] {
        let persistence = PersistenceController.shared
        let context = persistence.container.viewContext

        return references.compactMap { reference in
            switch reference.kind {
                case .library:
                    guard let url = URL(string: reference.identifier),
                          let objectID = persistence.container
                            .persistentStoreCoordinator
                            .managedObjectID(
                                forURIRepresentation: url
                            ),
                          let object = try? context.existingObject(
                            with: objectID
                          ),
                          let file = object as? File,
                          !file.inTrash else {
                        return nil
                    }
                    return .libraryFile(
                        objectID: objectID,
                        name: file.name
                            ?? String(localizable: .generalUnknown)
                    )

                case .local:
                    guard let url = URL(string: reference.identifier),
                          FileManager.default.fileExists(atPath: url.path)
                    else {
                        return nil
                    }
                    return .localFile(url: url)
            }
        }
    }
}
#endif
