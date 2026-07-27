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

enum ScreenAnnotationSaveFormat: String, CaseIterable, Codable, Hashable {
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

    func bitmapProperties(
        jpegCompressionFactor: Double
    ) -> [NSBitmapImageRep.PropertyKey: Any] {
        switch self {
            case .raw, .png:
                [:]
            case .jpeg:
                [.compressionFactor: jpegCompressionFactor]
        }
    }
}

enum ScreenAnnotationImageQuality: String, CaseIterable, Codable, Hashable {
    case original
    case balanced
    case compact

    var title: String {
        switch self {
            case .original:
                "Original"
            case .balanced:
                "Balanced"
            case .compact:
                "Compact"
        }
    }

    var maximumPixelsPerPoint: CGFloat? {
        switch self {
            case .original:
                nil
            case .balanced:
                1.5
            case .compact:
                1
        }
    }

    var maximumLongEdge: CGFloat? {
        switch self {
            case .original:
                nil
            case .balanced:
                3_072
            case .compact:
                1_920
        }
    }

    var jpegCompressionFactor: Double {
        switch self {
            case .original:
                0.92
            case .balanced:
                0.86
            case .compact:
                0.78
        }
    }

    var rawImageFormat: ScreenAnnotationSaveFormat {
        self == .original ? .png : .jpeg
    }
}

@MainActor
final class ScreenAnnotationSaveConfiguration: ObservableObject {
    private enum DestinationKind: String, Codable, Hashable {
        case file
        case clipboard
        case customLocation
    }

    private struct DestinationReference: Codable, Hashable {
        enum Kind: String, Codable {
            case newFile
            case clipboard
            case customLocation
            case library
            case local
        }

        let kind: Kind
        let identifier: String?
    }

    private struct PersistedPreferences: Codable {
        let destination: DestinationReference
        let fileDestination: DestinationReference
        let format: ScreenAnnotationSaveFormat
        let formatsByDestination: [String: ScreenAnnotationSaveFormat]?
        let imageQuality: ScreenAnnotationImageQuality?
        let qualitiesByDestination: [String: ScreenAnnotationImageQuality]?
    }

    private static let recentFileDestinationsKey =
        "ScreenAnnotationRecentFileDestinations"
    private static let preferencesKey =
        "ScreenAnnotationSavePreferences"
    private static let recentFileDestinationLimit = 5

    @Published private(set) var destination: ScreenAnnotationSaveDestination
    @Published private(set) var fileDestination: ScreenAnnotationSaveDestination
    @Published private(set) var recentFileDestinations:
        [ScreenAnnotationSaveDestination] = []
    @Published var format: ScreenAnnotationSaveFormat {
        didSet {
            preferredFormats[Self.kind(for: destination)] = format
            savePreferences()
        }
    }
    @Published var imageQuality: ScreenAnnotationImageQuality {
        didSet {
            preferredQualities[Self.kind(for: destination)] = imageQuality
            savePreferences()
        }
    }

    private var recentFileReferences: [DestinationReference] = []
    private var preferredFormats: [
        DestinationKind: ScreenAnnotationSaveFormat
    ]
    private var preferredQualities: [
        DestinationKind: ScreenAnnotationImageQuality
    ]

    init(
        destination: ScreenAnnotationSaveDestination = .newFile,
        format: ScreenAnnotationSaveFormat = .raw,
        imageQuality: ScreenAnnotationImageQuality = .balanced
    ) {
        let storedRecentFileReferences = Self.loadRecentFileReferences()
        recentFileReferences = storedRecentFileReferences.filter {
            Self.resolveDestination(from: $0) != nil
        }
        recentFileDestinations = Self.resolveDestinations(
            from: recentFileReferences
        )
        if recentFileReferences.count != storedRecentFileReferences.count {
            Self.saveRecentFileReferences(recentFileReferences)
        }

        let preferences = Self.loadPreferences()
        let restoredDestination = preferences.flatMap {
            Self.resolveDestination(from: $0.destination)
        }
        let restoredFileDestination = preferences.flatMap {
            Self.resolveDestination(from: $0.fileDestination)
        }
        var preferredFormats = Self.defaultPreferredFormats
        if let persistedFormats = preferences?.formatsByDestination {
            for (rawKind, format) in persistedFormats {
                guard let kind = DestinationKind(rawValue: rawKind) else {
                    continue
                }
                preferredFormats[kind] = format
            }
        }
        var preferredQualities = Self.defaultPreferredQualities
        if let persistedQualities = preferences?.qualitiesByDestination {
            for (rawKind, quality) in persistedQualities {
                guard let kind = DestinationKind(rawValue: rawKind) else {
                    continue
                }
                preferredQualities[kind] = quality
            }
        }

        let initialDestination = restoredDestination ?? destination
        if let preferences,
           preferences.formatsByDestination == nil {
            preferredFormats[Self.kind(for: initialDestination)] =
                preferences.format
        } else if preferences == nil {
            preferredFormats[Self.kind(for: destination)] = format
        }
        if let preferences,
           preferences.qualitiesByDestination == nil,
           let imageQuality = preferences.imageQuality {
            preferredQualities[Self.kind(for: initialDestination)] =
                imageQuality
        } else if preferences == nil {
            preferredQualities[Self.kind(for: destination)] = imageQuality
        }
        let initialFileDestination = if let restoredFileDestination,
                                        restoredFileDestination.isExcalidrawFile {
            restoredFileDestination
        } else if initialDestination.isExcalidrawFile {
            initialDestination
        } else {
            ScreenAnnotationSaveDestination.newFile
        }

        self.destination = initialDestination
        self.fileDestination = initialFileDestination
        self.preferredFormats = preferredFormats
        self.preferredQualities = preferredQualities
        self.format = preferredFormats[
            Self.kind(for: initialDestination)
        ] ?? format
        self.imageQuality = preferredQualities[
            Self.kind(for: initialDestination)
        ] ?? imageQuality
        savePreferences()
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
        format = preferredFormats[
            Self.kind(for: destination)
        ] ?? Self.defaultFormat(for: destination)
        imageQuality = preferredQualities[
            Self.kind(for: destination)
        ] ?? .balanced
    }

    func selectFileDestination(
        _ destination: ScreenAnnotationSaveDestination
    ) {
        guard destination.isExcalidrawFile else { return }
        fileDestination = destination
        self.destination = destination
        format = preferredFormats[.file] ?? .raw
        imageQuality = preferredQualities[.file] ?? .balanced
    }

    func recordSuccessfulSave(
        to destination: ScreenAnnotationSaveDestination
    ) {
        guard let reference = Self.fileReference(for: destination) else {
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

    private static func fileReference(
        for destination: ScreenAnnotationSaveDestination
    ) -> DestinationReference? {
        switch destination {
            case .libraryFile(let objectID, _):
                return DestinationReference(
                    kind: .library,
                    identifier: objectID.uriRepresentation().absoluteString
                )
            case .localFile(let url):
                return DestinationReference(
                    kind: .local,
                    identifier: url.standardizedFileURL.absoluteString
                )
            case .newFile, .clipboard, .customLocation:
                return nil
        }
    }

    private static func preferenceReference(
        for destination: ScreenAnnotationSaveDestination
    ) -> DestinationReference {
        switch destination {
            case .newFile:
                DestinationReference(kind: .newFile, identifier: nil)
            case .clipboard:
                DestinationReference(kind: .clipboard, identifier: nil)
            case .customLocation:
                DestinationReference(kind: .customLocation, identifier: nil)
            case .libraryFile, .localFile:
                fileReference(for: destination)
                    ?? DestinationReference(kind: .newFile, identifier: nil)
        }
    }

    private static func loadRecentFileReferences() -> [DestinationReference] {
        guard let data = UserDefaults.standard.data(
            forKey: recentFileDestinationsKey
        ) else {
            return []
        }
        return (try? JSONDecoder().decode(
            [DestinationReference].self,
            from: data
        )) ?? []
    }

    private static func saveRecentFileReferences(
        _ references: [DestinationReference]
    ) {
        guard let data = try? JSONEncoder().encode(references) else {
            return
        }
        UserDefaults.standard.set(
            data,
            forKey: recentFileDestinationsKey
        )
    }

    private static func loadPreferences() -> PersistedPreferences? {
        guard let data = UserDefaults.standard.data(
            forKey: preferencesKey
        ) else {
            return nil
        }
        return try? JSONDecoder().decode(
            PersistedPreferences.self,
            from: data
        )
    }

    private func savePreferences() {
        let preferences = PersistedPreferences(
            destination: Self.preferenceReference(for: destination),
            fileDestination: Self.preferenceReference(for: fileDestination),
            format: format,
            formatsByDestination: Dictionary(
                uniqueKeysWithValues: preferredFormats.map {
                    ($0.key.rawValue, $0.value)
                }
            ),
            imageQuality: imageQuality,
            qualitiesByDestination: Dictionary(
                uniqueKeysWithValues: preferredQualities.map {
                    ($0.key.rawValue, $0.value)
                }
            )
        )
        guard let data = try? JSONEncoder().encode(preferences) else {
            return
        }
        UserDefaults.standard.set(data, forKey: Self.preferencesKey)
    }

    private static func resolveDestinations(
        from references: [DestinationReference]
    ) -> [ScreenAnnotationSaveDestination] {
        references.compactMap(resolveDestination)
    }

    private static let defaultPreferredFormats: [
        DestinationKind: ScreenAnnotationSaveFormat
    ] = [
        .file: .raw,
        .clipboard: .png,
        .customLocation: .png,
    ]

    private static let defaultPreferredQualities: [
        DestinationKind: ScreenAnnotationImageQuality
    ] = [
        .file: .balanced,
        .clipboard: .balanced,
        .customLocation: .balanced,
    ]

    private static func kind(
        for destination: ScreenAnnotationSaveDestination
    ) -> DestinationKind {
        switch destination {
            case .newFile, .libraryFile, .localFile:
                .file
            case .clipboard:
                .clipboard
            case .customLocation:
                .customLocation
        }
    }

    private static func defaultFormat(
        for destination: ScreenAnnotationSaveDestination
    ) -> ScreenAnnotationSaveFormat {
        defaultPreferredFormats[kind(for: destination)] ?? .raw
    }

    private static func resolveDestination(
        from reference: DestinationReference
    ) -> ScreenAnnotationSaveDestination? {
        switch reference.kind {
            case .newFile:
                return .newFile
            case .clipboard:
                return .clipboard
            case .customLocation:
                return .customLocation
            case .library:
                guard let identifier = reference.identifier,
                      let url = URL(string: identifier) else {
                    return nil
                }
                let persistence = PersistenceController.shared
                let context = persistence.container.viewContext
                guard let objectID = persistence.container
                    .persistentStoreCoordinator
                    .managedObjectID(forURIRepresentation: url),
                    let object = try? context.existingObject(with: objectID),
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
                guard let identifier = reference.identifier,
                      let url = URL(string: identifier),
                      FileManager.default.fileExists(atPath: url.path) else {
                    return nil
                }
                return .localFile(url: url)
        }
    }
}
#endif
