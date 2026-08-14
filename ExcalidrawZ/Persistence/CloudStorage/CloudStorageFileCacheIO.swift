//
//  CloudStorageFileCacheIO.swift
//  ExcalidrawZ
//

import Foundation

/// Serializes potentially large document payload IO away from the main actor.
/// CloudStorageDocumentStore remains the state machine and awaits these
/// operations before publishing the corresponding metadata or sync state.
actor CloudStorageFileCacheIO {
    private let fileManager: FileManager
    private var generationsByURL: [URL: UInt64] = [:]
    private var nextGeneration: UInt64 = 1

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func readIfExists(at url: URL) throws -> Data? {
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        return try Data(contentsOf: url)
    }

    func read(at url: URL) throws -> Data {
        try Data(contentsOf: url)
    }

    @discardableResult
    func write(_ data: Data, to url: URL) throws -> UInt64 {
        try writeData(data, to: url)
        return advanceGeneration(for: url)
    }

    /// Temporary upload files do not participate in cache conflict detection.
    /// Keeping them out of the generation table avoids retaining one UUID URL
    /// for every upload performed during the process lifetime.
    func writeTemporary(_ data: Data, to url: URL) throws {
        try writeData(data, to: url)
    }

    /// Atomically compares and writes inside this actor so a remote install
    /// cannot slip between a local save's comparison and replacement.
    func writeIfDifferent(_ data: Data, to url: URL) throws -> Bool {
        if fileManager.fileExists(atPath: url.path),
           try Data(contentsOf: url) == data {
            return false
        }
        try write(data, to: url)
        return true
    }

    func generation(at url: URL) -> UInt64 {
        let key = url.standardizedFileURL
        if let generation = generationsByURL[key] {
            return generation
        }
        let generation = takeNextGeneration()
        generationsByURL[key] = generation
        return generation
    }

    /// Installs a remote candidate only if no cache mutation occurred since
    /// the caller began downloading it.
    func write(
        _ data: Data,
        to url: URL,
        ifGenerationIs expectedGeneration: UInt64
    ) throws -> Bool {
        guard generation(at: url) == expectedGeneration else { return false }
        try write(data, to: url)
        return true
    }

    func copyToTemporary(from sourceURL: URL, to destinationURL: URL) throws {
        try writeData(Data(contentsOf: sourceURL), to: destinationURL)
    }

    func removeIfExists(at url: URL) throws {
        if fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
        advanceGeneration(for: url)
    }

    func moveIfExists(from sourceURL: URL, to destinationURL: URL) throws -> Bool {
        guard fileManager.fileExists(atPath: sourceURL.path) else { return false }
        try fileManager.createDirectory(
            at: destinationURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if fileManager.fileExists(atPath: destinationURL.path) {
            try fileManager.removeItem(at: destinationURL)
        }
        try fileManager.moveItem(at: sourceURL, to: destinationURL)
        advanceGeneration(for: sourceURL)
        advanceGeneration(for: destinationURL)
        return true
    }

    func removeDirectoryIfExists(at url: URL) throws {
        let directoryPath = url.standardizedFileURL.path + "/"
        generationsByURL = generationsByURL.filter {
            !$0.key.path.hasPrefix(directoryPath)
        }
        if fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
    }

    func modificationDate(at url: URL) throws -> Date? {
        try url.resourceValues(
            forKeys: [.contentModificationDateKey]
        ).contentModificationDate
    }

    @discardableResult
    private func advanceGeneration(for url: URL) -> UInt64 {
        let key = url.standardizedFileURL
        let generation = takeNextGeneration()
        generationsByURL[key] = generation
        return generation
    }

    private func takeNextGeneration() -> UInt64 {
        let generation = nextGeneration
        nextGeneration &+= 1
        return generation
    }

    private func writeData(_ data: Data, to url: URL) throws {
        try fileManager.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: url, options: .atomic)
    }
}
