//
//  AppStore.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 2023/7/25.
//

import SwiftUI
import WebKit
import Combine
import Logging
import UniformTypeIdentifiers

import ChocofordUI

struct ExportedImageData {
    var name: String
    var data: Data
    var url: URL
    var temporaryDirectory: URL? = nil

    func removeTemporaryFile() {
        guard let temporaryDirectory else { return }
        try? FileManager.default.removeItem(at: temporaryDirectory)
    }
}

final class ExportState: ObservableObject {
    let logger = Logger(label: "ExportState")
    enum Status {
        case notRequested
        case loading
        case finish
    }
    
    var excalidrawWebCoordinator: ExcalidrawCanvasView.Coordinator?
    var excalidrawCollaborationWebCoordinator: ExcalidrawCanvasView.Coordinator?
    
    @Published var status: Status = .notRequested
    var download: WKDownload?
    var url: URL?
    
    enum ExportType {
        case image, file
    }
    
    func requestExport(type: ExportType) async throws {
        guard let excalidrawWebCoordinator else {
            struct WebCoordinatorNotReadyError: Error {}
            throw WebCoordinatorNotReadyError()
        }
        switch type {
            case .image:
                  try await excalidrawWebCoordinator.exportPNG()
            case .file:
                break
        }
    }
    
    func beginExport(url: URL, download: WKDownload) {
        self.logger.info("Begin export <url: \(url)>")
        self.status = .loading
        self.url = url
        self.download = download
    }
    
    func finishExport(download: WKDownload) {
        if download == self.download {
            self.logger.info("Finish export")
            self.status = .finish
        }
    }
    
    enum ImageType {
        case png
        case svg
    }
    
    func exportCurrentFileToImage(
        type: ImageType,
        embedScene: Bool,
        withBackground: Bool,
        colorScheme: ColorScheme,
        exportScale: Int = 1
    ) async throws -> ExportedImageData {
        let dbFile = await self.excalidrawWebCoordinator?.parent?.file
        let collaborationFile = await self.excalidrawCollaborationWebCoordinator?.parent?.file
        
        guard let file = dbFile ?? collaborationFile else {
            struct NoFileError: LocalizedError {
                var errorDescription: String? {
                    "Miss current file"
                }
            }
            throw NoFileError()
        }
        return try await exportExcalidrawElementsToImage(
            elements: file.elements,
            type: type,
            name: file.name ?? String(localizable: .generalUntitled),
            embedScene: embedScene,
            withBackground: withBackground,
            colorScheme: colorScheme,
            exportScale: exportScale
        )
    }
    
    func exportExcalidrawElementsToImage(
        elements: [ExcalidrawElement],
        files: [String: ExcalidrawFile.ResourceFile]? = nil,
        coordinator: ExcalidrawCore? = nil,
        type: ImageType,
        name: String,
        embedScene: Bool,
        withBackground: Bool,
        colorScheme: ColorScheme,
        exportScale: Int = 1
    ) async throws -> ExportedImageData {
        guard let coordinator = coordinator ?? excalidrawWebCoordinator else {
            struct NoWebCoordinatorError: LocalizedError {
                var errorDescription: String? {
                    "Miss web coordinator"
                }
            }
            throw NoWebCoordinatorError()
        }
        
        let imageData: Data
        let utType: UTType
        switch type {
            case .png:
                imageData = try await coordinator.exportElementsToPNGData(
                    elements: elements,
                    files: files,
                    embedScene: embedScene,
                    withBackground: withBackground,
                    colorScheme: colorScheme,
                    exportScale: exportScale
                )
                utType = embedScene ? .excalidrawPNG : .png
            case .svg:
                imageData = try await coordinator.exportElementsToSVGData(
                    elements: elements,
                    files: files,
                    embedScene: embedScene,
                    withBackground: withBackground,
                    colorScheme: colorScheme
                )
                utType = embedScene ? .excalidrawSVG :.svg
        }
        
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let filename = name
        let url = directory.appendingPathComponent(filename, conformingTo: utType)
        do {
            try imageData.write(to: url)
        } catch {
            try? FileManager.default.removeItem(at: directory)
            throw error
        }
        
        return ExportedImageData(
            name: filename,
            data: imageData,
            url: url,
            temporaryDirectory: directory
        )
    }
}
