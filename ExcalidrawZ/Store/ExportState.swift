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
}

final class ExportState: ObservableObject {
    let logger = Logger(label: "ExportState")
    enum Status {
        case notRequested
        case loading
        case finish
    }
    
    var excalidrawWebCoordinator: ExcalidrawView.Coordinator?
    var excalidrawCollaborationWebCoordinator: ExcalidrawView.Coordinator?
    
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
        colorScheme: ColorScheme
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
            name: file.name ?? "Untitled",
            embedScene: embedScene,
            withBackground: withBackground,
            colorScheme: colorScheme
        )
    }
    
    func exportExcalidrawElementsToImage(
        elements: [ExcalidrawElement],
        type: ImageType,
        name: String,
        embedScene: Bool,
        withBackground: Bool,
        colorScheme: ColorScheme
    ) async throws -> ExportedImageData {
        guard let excalidrawWebCoordinator else {
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
                imageData = try await excalidrawWebCoordinator.exportElementsToPNGData(
                    elements: elements,
                    embedScene: embedScene,
                    withBackground: withBackground,
                    colorScheme: colorScheme
                )
                utType = embedScene ? .excalidrawPNG : .png
            case .svg:
                imageData = try await excalidrawWebCoordinator.exportElementsToSVGData(
                    elements: elements,
                    embedScene: embedScene,
                    withBackground: withBackground,
                    colorScheme: colorScheme
                )
                utType = embedScene ? .excalidrawSVG :.svg
        }
        
        let directory: URL = try getTempDirectory()
        let filename = name
        let url = directory.appendingPathComponent(filename, conformingTo: utType)
        try imageData.write(to: url)
        
        return ExportedImageData(
            name: filename,
            data: imageData,
            url: url
        )
    }
}
