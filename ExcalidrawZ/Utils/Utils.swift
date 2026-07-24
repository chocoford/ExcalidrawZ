//
//  Utils.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 2022/12/26.
//

import Foundation
import SwiftUI
import CoreData
import Logging
#if canImport(AppKit)
import AppKit
#endif

import WebKit

private let utilitiesLogger = Logger(label: "Utilities")

func loadResource<T: Decodable>(_ filename: String) -> T {
    let data: Data

    guard let file = Bundle.main.url(forResource: filename, withExtension: nil)
        else {
            fatalError("Couldn't find \(filename) in main bundle.")
    }

    do {
        data = try Data(contentsOf: file)
    } catch {
        fatalError("Couldn't load \(filename) from main bundle:\n\(error)")
    }

    do {
        let decoder = JSONDecoder()
        return try decoder.decode(T.self, from: data)
    } catch {
        fatalError("Couldn't parse \(filename) as \(T.self):\n\(error.localizedDescription)")
    }
}


#if canImport(AppKit)

func getBackupsDir() throws -> URL {
    let filemanager = FileManager.default
    let supportDir = try filemanager.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
    let backupsDir = supportDir.appendingPathComponent("backups", conformingTo: .directory)
    if !filemanager.fileExists(at: backupsDir) {
        try filemanager.createDirectory(at: backupsDir, withIntermediateDirectories: true)
    }
    return backupsDir
}

enum BackupFilesReason {
    case regular
    case unlockedContent

    var replacesExistingToday: Bool {
        switch self {
            case .regular:
                false
            case .unlockedContent:
                true
        }
    }

    var includesUnlockedLockedFiles: Bool {
        switch self {
            case .regular:
                false
            case .unlockedContent:
                true
        }
    }
}

@discardableResult
func backupFiles(
    context: NSManagedObjectContext,
    reason: BackupFilesReason = .regular
) async throws -> Bool {
    let fileManager = FileManager.default
    let backupsDir = try getBackupsDir()
    let replaceExistingToday = reason.replacesExistingToday

    let today = Date()
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd"
    let backupFolderName = formatter.string(from: today)
    let exportURL = backupsDir.appendingPathComponent(backupFolderName, conformingTo: .directory)
    let existingBackupExists = fileManager.fileExists(at: exportURL)
    if existingBackupExists && !replaceExistingToday { return false }

    let workingExportURL: URL
    if replaceExistingToday {
        workingExportURL = backupsDir.appendingPathComponent(
            ".\(backupFolderName)-staging-\(UUID().uuidString)",
            conformingTo: .directory
        )
    } else {
        workingExportURL = exportURL
    }
    var didInstallWorkingBackup = !replaceExistingToday
    defer {
        if replaceExistingToday && !didInstallWorkingBackup {
            try? fileManager.removeItem(at: workingExportURL)
        }
    }

    // Cloud
    let cloudExportURL = workingExportURL.appendingPathComponent("Cloud", conformingTo: .directory)
    do {
        utilitiesLogger.debug("Starting cloud backup at \(cloudExportURL.path)")
        try fileManager.createDirectory(at: cloudExportURL, withIntermediateDirectories: true)
        try await backupAllCloudFiles(
            to: cloudExportURL,
            context: context,
            includeLockedFiles: reason.includesUnlockedLockedFiles
        )
    } catch let error as EncryptedContentError where error.isContentLocked {
        utilitiesLogger.debug("Skipping backup because locked files are not unlocked")
        try? fileManager.removeItem(at: workingExportURL)
        return false
    } catch {
        utilitiesLogger.warning("Cloud backup completed with error: \(error)")
    }
    // Local
    let localExportURL = workingExportURL.appendingPathComponent("Local", conformingTo: .directory)
    do {
        utilitiesLogger.debug("Starting local backup at \(localExportURL.path)")
        try fileManager.createDirectory(at: localExportURL, withIntermediateDirectories: true)
        try await backupLocalFolders(to: localExportURL)
    } catch {
        utilitiesLogger.warning("Local backup completed with error: \(error)")
    }

    if replaceExistingToday {
        if existingBackupExists {
            try fileManager.removeItem(at: exportURL)
        }
        try fileManager.moveItem(at: workingExportURL, to: exportURL)
        didInstallWorkingBackup = true
    }
    
    // clean
    let backupFolders: [URL] = try fileManager.contentsOfDirectory(
        at: backupsDir,
        includingPropertiesForKeys: [.creationDateKey],
        options: .skipsHiddenFiles
    ).filter { $0.hasDirectoryPath && formatter.date(from: $0.lastPathComponent) != nil }
    
    let sortedFolders = backupFolders.compactMap { folder -> (URL, Date)? in
        if let date = formatter.date(from: folder.lastPathComponent) {
            return (folder, date)
        }
        return nil
    }.sorted { $0.1 > $1.1 }
    
    var foldersToKeep: [URL] = []
    var seenMonths: Set<String> = []
    var seenYears: Set<String> = []
    for (folder, date) in sortedFolders {
        let daysDifference = Calendar.current.dateComponents([.day], from: date, to: today).day ?? 0
        if daysDifference <= 7 {
            foldersToKeep.append(folder)
        } else if daysDifference <= 365 {
            let monthKey = formatter.string(from: date).prefix(7) // yyyy-MM
            if !seenMonths.contains(String(monthKey)) {
                seenMonths.insert(String(monthKey))
                foldersToKeep.append(folder)
            }
        } else {
            let yearKey = formatter.string(from: date).prefix(4) // yyyy
            if !seenYears.contains(String(yearKey)) {
                seenYears.insert(String(yearKey))
                foldersToKeep.append(folder)
            }
        }
    }
    let foldersToDelete = Set(sortedFolders.map { $0.0 }).subtracting(foldersToKeep)
    utilitiesLogger.debug("Backup retention keeps \(foldersToKeep.count) folder(s), deletes \(foldersToDelete.count)")
    for folder in foldersToDelete {
        do {
            try fileManager.removeItem(at: folder)
        } catch {
            utilitiesLogger.warning("Failed to remove old backup folder \(folder.path): \(error)")
        }
    }

    return true
}

private func backupLocalFolders(to localExportURL: URL) async throws {
    let context = PersistenceController.shared.container.newBackgroundContext()
    try await context.perform {
        let fetchRequest = NSFetchRequest<LocalFolder>(entityName: "LocalFolder")
        fetchRequest.predicate = NSPredicate(format: "parent = nil")
        let allFolders = try context.fetch(fetchRequest)
        for folder in allFolders {
            // Files in iCloud will not be copied if not downloaded.
            try folder.withSecurityScopedURL { scopedURL in
                let fileCoordinator = NSFileCoordinator()
                var coordinationError: NSError?
                fileCoordinator.coordinate(readingItemAt: scopedURL, error: &coordinationError) { url in
                    do {
                        try copyEncryptedBackupItem(
                            at: url,
                            to: localExportURL.appendingPathComponent(url.lastPathComponent, conformingTo: .directory)
                        )
                    } catch {
                        utilitiesLogger.warning("Failed to copy local folder during backup \(url.path): \(error)")
                    }
                }
                if let coordinationError {
                    throw coordinationError
                }
            }
        }
    }
}

private func copyEncryptedBackupItem(at sourceURL: URL, to destinationURL: URL) throws {
    let fileManager = FileManager.default
    let values = try sourceURL.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey])

    if values.isDirectory == true {
        try fileManager.createDirectory(at: destinationURL, withIntermediateDirectories: true)
        let children = try fileManager.contentsOfDirectory(
            at: sourceURL,
            includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        )
        for child in children {
            try copyEncryptedBackupItem(
                at: child,
                to: destinationURL.appendingPathComponent(child.lastPathComponent)
            )
        }
        return
    }

    guard values.isRegularFile == true else { return }

    try fileManager.createDirectory(
        at: destinationURL.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    let encryptedData = try EncryptedBackupService.encrypt(Data(contentsOf: sourceURL))
    try encryptedData.write(to: destinationURL, options: .atomic)
}

struct BackupRecoveryKeyRewrapResult: Sendable {
    let rewrappedCount: Int
    let failedCount: Int
}

struct BackupEncryptedFileDeletionResult: Sendable {
    let deletedCount: Int
    let failedCount: Int
}

struct BackupEncryptedFileValidationResult: Sendable {
    let validCount: Int
    let failedCount: Int
}

func backupsContainEncryptedExcalidrawFiles() async -> Bool {
    await Task.detached(priority: .utility) {
        do {
            return try backupDirectoryContainsEncryptedExcalidrawFiles(try getBackupsDir())
        } catch {
            utilitiesLogger.warning("Failed to scan backups for locked content: \(error)")
            return false
        }
    }.value
}

func countEncryptedBackupExcalidrawFiles() async -> Int {
    await Task.detached(priority: .utility) {
        do {
            return try countEncryptedExcalidrawFiles(in: try getBackupsDir())
        } catch {
            utilitiesLogger.warning("Failed to count encrypted backup files: \(error)")
            return 0
        }
    }.value
}

func countEncryptedBackupExcalidrawFilesStrict() async throws -> Int {
    try await Task.detached(priority: .utility) {
        try countEncryptedExcalidrawFiles(in: try getBackupsDir())
    }.value
}

func validateEncryptedBackupExcalidrawFiles(with recoveryKey: RecoveryKey) async -> BackupEncryptedFileValidationResult {
    await Task.detached(priority: .utility) {
        do {
            return try validateEncryptedExcalidrawFiles(
                in: try getBackupsDir(),
                recoveryKey: recoveryKey
            )
        } catch {
            utilitiesLogger.warning("Failed to validate encrypted backup files: \(error)")
            return BackupEncryptedFileValidationResult(validCount: 0, failedCount: 1)
        }
    }.value
}

func deleteEncryptedBackupExcalidrawFiles() async -> BackupEncryptedFileDeletionResult {
    await Task.detached(priority: .utility) {
        do {
            return try deleteEncryptedExcalidrawFiles(in: try getBackupsDir())
        } catch {
            utilitiesLogger.warning("Failed to delete encrypted backup files: \(error)")
            return BackupEncryptedFileDeletionResult(deletedCount: 0, failedCount: 1)
        }
    }.value
}

func canUnlockEncryptedBackupExcalidrawFile(with recoveryKey: RecoveryKey) async -> Bool {
    await Task.detached(priority: .utility) {
        do {
            return try canUnlockEncryptedExcalidrawFile(
                in: try getBackupsDir(),
                recoveryKey: recoveryKey
            )
        } catch {
            utilitiesLogger.warning("Failed to validate encrypted backup Recovery Key: \(error)")
            return false
        }
    }.value
}

func backupDirectoryContainsEncryptedExcalidrawFiles(_ directory: URL) throws -> Bool {
    try countEncryptedExcalidrawFiles(in: directory, stopAfterFirstMatch: true) > 0
}

private func countEncryptedExcalidrawFiles(
    in directory: URL,
    stopAfterFirstMatch: Bool = false
) throws -> Int {
    let fileManager = FileManager.default
    guard let enumerator = fileManager.enumerator(
        at: directory,
        includingPropertiesForKeys: [.isRegularFileKey],
        options: [.skipsHiddenFiles]
    ) else {
        return 0
    }

    var count = 0
    var visitedCount = 0
    while let url = enumerator.nextObject() as? URL {
        visitedCount += 1
        if visitedCount.isMultiple(of: 20) {
            try Task.checkCancellation()
        }

        guard url.pathExtension == "excalidraw" else { continue }
        let values = try? url.resourceValues(forKeys: [.isRegularFileKey])
        guard values?.isRegularFile == true else { continue }

        let data = try Data(contentsOf: url)
        if EncryptedContentService.isEncryptedEnvelope(data) {
            count += 1
            if stopAfterFirstMatch {
                return count
            }
        }
    }

    return count
}

private func validateEncryptedExcalidrawFiles(
    in directory: URL,
    recoveryKey: RecoveryKey
) throws -> BackupEncryptedFileValidationResult {
    let fileManager = FileManager.default
    guard let enumerator = fileManager.enumerator(
        at: directory,
        includingPropertiesForKeys: [.isRegularFileKey],
        options: [.skipsHiddenFiles]
    ) else {
        return BackupEncryptedFileValidationResult(validCount: 0, failedCount: 0)
    }

    var validCount = 0
    var failedCount = 0
    var visitedCount = 0
    while let url = enumerator.nextObject() as? URL {
        visitedCount += 1
        if visitedCount.isMultiple(of: 20) {
            try Task.checkCancellation()
        }

        guard url.pathExtension == "excalidraw" else { continue }
        let values = try? url.resourceValues(forKeys: [.isRegularFileKey])
        guard values?.isRegularFile == true else { continue }

        let data = try Data(contentsOf: url)
        guard EncryptedContentService.isEncryptedEnvelope(data) else { continue }

        do {
            _ = try EncryptedContentService.unlockContentKey(
                data,
                recoveryKey: recoveryKey
            )
            validCount += 1
        } catch {
            failedCount += 1
        }
    }

    return BackupEncryptedFileValidationResult(
        validCount: validCount,
        failedCount: failedCount
    )
}

private func deleteEncryptedExcalidrawFiles(in directory: URL) throws -> BackupEncryptedFileDeletionResult {
    let fileManager = FileManager.default
    guard let enumerator = fileManager.enumerator(
        at: directory,
        includingPropertiesForKeys: [.isRegularFileKey],
        options: [.skipsHiddenFiles]
    ) else {
        return BackupEncryptedFileDeletionResult(deletedCount: 0, failedCount: 0)
    }

    var deletedCount = 0
    var failedCount = 0
    var visitedCount = 0

    while let url = enumerator.nextObject() as? URL {
        visitedCount += 1
        if visitedCount.isMultiple(of: 20) {
            try Task.checkCancellation()
        }

        guard url.pathExtension == "excalidraw" else { continue }
        let values = try? url.resourceValues(forKeys: [.isRegularFileKey])
        guard values?.isRegularFile == true else { continue }

        do {
            let data = try Data(contentsOf: url)
            guard EncryptedContentService.isEncryptedEnvelope(data) else { continue }
            try fileManager.removeItem(at: url)
            deletedCount += 1
        } catch {
            failedCount += 1
            utilitiesLogger.warning("Failed to delete encrypted backup file \(url.path): \(error)")
        }
    }

    return BackupEncryptedFileDeletionResult(
        deletedCount: deletedCount,
        failedCount: failedCount
    )
}

private func canUnlockEncryptedExcalidrawFile(
    in directory: URL,
    recoveryKey: RecoveryKey
) throws -> Bool {
    let fileManager = FileManager.default
    guard let enumerator = fileManager.enumerator(
        at: directory,
        includingPropertiesForKeys: [.isRegularFileKey],
        options: [.skipsHiddenFiles]
    ) else {
        return false
    }

    var visitedCount = 0
    while let url = enumerator.nextObject() as? URL {
        visitedCount += 1
        if visitedCount.isMultiple(of: 20) {
            try Task.checkCancellation()
        }

        guard url.pathExtension == "excalidraw" else { continue }
        let values = try? url.resourceValues(forKeys: [.isRegularFileKey])
        guard values?.isRegularFile == true else { continue }

        let data = try Data(contentsOf: url)
        guard EncryptedContentService.isEncryptedEnvelope(data) else { continue }

        do {
            _ = try EncryptedContentService.unlockContentKey(
                data,
                recoveryKey: recoveryKey
            )
            return true
        } catch {
            continue
        }
    }

    return false
}

func rewrapEncryptedBackupFilesRecoveryKey(
    oldRecoveryKey: RecoveryKey,
    newRecoveryKey: RecoveryKey
) async -> BackupRecoveryKeyRewrapResult {
    let fileManager = FileManager.default
    do {
        let backupsDir = try getBackupsDir()
        guard let enumerator = fileManager.enumerator(
            at: backupsDir,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return BackupRecoveryKeyRewrapResult(rewrappedCount: 0, failedCount: 0)
        }

        var rewrappedCount = 0
        var failedCount = 0
        var visitedCount = 0

        while let url = enumerator.nextObject() as? URL {
            try Task.checkCancellation()
            visitedCount += 1
            if visitedCount.isMultiple(of: 20) {
                await Task.yield()
            }

            guard url.pathExtension == "excalidraw" else { continue }
            let values = try? url.resourceValues(forKeys: [.isRegularFileKey])
            guard values?.isRegularFile == true else { continue }

            do {
                let data = try Data(contentsOf: url)
                guard EncryptedContentService.isEncryptedEnvelope(data) else { continue }

                let unlockedKey = try EncryptedContentService.unlockContentKey(
                    data,
                    recoveryKey: oldRecoveryKey
                )
                let rewrapped = try EncryptedContentService.rewrapRecoveryKey(
                    existingEnvelopeData: data,
                    unlockedKey: unlockedKey,
                    newRecoveryKey: newRecoveryKey
                )
                try rewrapped.write(to: url, options: .atomic)
                rewrappedCount += 1
            } catch {
                failedCount += 1
                utilitiesLogger.warning("Failed to reset Recovery Key for backup file \(url.path): \(error)")
            }
        }

        return BackupRecoveryKeyRewrapResult(
            rewrappedCount: rewrappedCount,
            failedCount: failedCount
        )
    } catch {
        utilitiesLogger.warning("Failed to scan backups for Recovery Key reset: \(error)")
        return BackupRecoveryKeyRewrapResult(rewrappedCount: 0, failedCount: 1)
    }
}

// MARK: - Export PDF
func exportPDF<Content: View>(@ViewBuilder content: () -> Content) {
    let printInfo = NSPrintInfo.shared
    printInfo.topMargin = 0
    printInfo.bottomMargin = 0
    printInfo.leftMargin = 0
    printInfo.rightMargin = 0
    printInfo.isHorizontallyCentered = true
    printInfo.isVerticallyCentered = true
    
    let hostingView = NSHostingView(rootView: content())

    let printOperation = NSPrintOperation(
        view: hostingView,
        printInfo: printInfo
    )
    
    printOperation.printPanel.options = [
        .showsCopies,
        .showsPageRange,
        .showsPaperSize,
        .showsOrientation,
        .showsScaling,
        .showsPrintSelection,
        .showsPageSetupAccessory,
        .showsPreview
    ]

    // 展示打印面板
    printOperation.run()
}

func exportPDF(name: String, svgURL: URL) async {
    let webView = await PrinterWebView(filename: name)
    await webView.print(fileURL: svgURL)
}

func renderPDFData(from svgURL: URL, filename: String) async throws -> Data {
    let webView = await PrinterWebView(filename: filename)
    return try await webView.exportPDFData(fileURL: svgURL)
}

func exportPDF(image: NSImage, name: String? = nil) {
    let printInfo = NSPrintInfo.shared
    printInfo.topMargin = 0
    printInfo.bottomMargin = 0
    printInfo.leftMargin = 0
    printInfo.rightMargin = 0

    let printImage = image
    
    let imageView = NSImageView(image: printImage)
    imageView.frame.size.width = printInfo.paperSize.width
    imageView.frame.size.height = printInfo.paperSize.width / printImage.width * printImage.size.height
    let printOperation = NSPrintOperation(
        view: imageView,
        printInfo: printInfo
    )
    
    printOperation.printPanel.options = [
        .showsCopies,
        .showsPageRange,
        .showsPaperSize,
        .showsOrientation,
        .showsScaling,
        .showsPrintSelection,
        .showsPageSetupAccessory,
        .showsPreview
    ]

    // 展示打印面板
    printOperation.run()
}
#elseif os(iOS)
func exportPDF(name: String, svgURL: URL) async -> URL? {
    let webView = await PrinterWebView(filename: name)
    return await webView.exportPDF(fileURL: svgURL)
}

func renderPDFData(from svgURL: URL, filename: String) async throws -> Data {
    let webView = await PrinterWebView(filename: filename)
    return try await webView.exportPDFData(fileURL: svgURL)
}

func exportPDF(image: UIImage, name: String? = nil, to url: URL? = nil) throws -> URL {
    // 设置 PDF 页面大小（例如 A4）
    let pageSize = CGSize(width: 595.2, height: 841.8) // A4 尺寸，单位为点 (1 point = 1/72 inch)
    
    // 创建 PDF 渲染器
    let pdfRenderer = UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: pageSize))
    
    // 确定临时文件保存路径
    let pdfURL = url ?? FileManager.default.temporaryDirectory.appendingPathComponent("\(name ?? "Excalidraw").pdf")
    
    // 计算图片缩放比例
    let scale = pageSize.width / image.size.width
    let scaledImageSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
    
    // 计算需要的页数
    let pageCount = Int(ceil(scaledImageSize.height / pageSize.height))
    
    do {
        try pdfRenderer.writePDF(to: pdfURL) { context in
            for page in 0..<pageCount {
                context.beginPage()
                let isLastPage = (page == pageCount - 1)
                let visibleRect = CGRect(
                    x: 0,
                    y: CGFloat(page) * pageSize.height / scale,
                    width: image.size.width,
                    height: isLastPage ? image.size.height - CGFloat(page) * pageSize.height / scale // 剩余高度
                    : pageSize.height / scale
                )
                
                let targetRect: CGRect
                if isLastPage {
                    // 按比例调整最后一页，使其内容填满页面
                    let remainingHeight = visibleRect.height * scale
                    targetRect = CGRect(
                        x: 0,
                        y: 0,
                        width: pageSize.width,
                        height: remainingHeight
                    )
                } else {
                    // 普通页面填满整页
                    targetRect = CGRect(
                        x: 0,
                        y: 0,
                        width: pageSize.width,
                        height: pageSize.height
                    )
                }
                
                // 裁剪并绘制当前页图片内容
                if let cgImage = image.cgImage?.cropping(to: visibleRect) {
                    UIImage(cgImage: cgImage).draw(in: targetRect)
                }
            }
        }
        
        return pdfURL
    } catch {
        utilitiesLogger.warning("Failed to create PDF: \(error)")
        throw error
    }
}


#endif

// MARK: - Clipboard
func entityURL(for objectID: NSManagedObjectID) throws -> URL {
    let uri = objectID.uriRepresentation().absoluteString
    guard let encodedURI = uri.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
          let url = URL(string: "excalidrawz://entity?objectURI=\(encodedURI)") else {
        struct InvalidURIError: LocalizedError {
            var errorDescription: String? {
                "Invalid File"
            }
        }
        
        throw InvalidURIError()
    }

    return url
}

func copyEntityURLToClipboard(objectID: NSManagedObjectID) throws {
    let url = try entityURL(for: objectID)
    
#if canImport(AppKit)
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(url.absoluteString, forType: .string)
#elseif canImport(UIKit)
    UIPasteboard.general.setObjects([url.absoluteString])
#endif
}

func getTempDirectory() throws -> URL {
    let fileManager: FileManager = FileManager.default
    let directory: URL
    if #available(macOS 13.0, *) {
        directory = try fileManager.url(
            for: .itemReplacementDirectory,
            in: .userDomainMask,
            appropriateFor: .applicationSupportDirectory,
            create: true
        )
    } else {
        directory = fileManager.temporaryDirectory
    }
    return directory
}


func flatFiles(in directory: URL) throws -> [URL] {
    let fileManager = FileManager.default
    var isDirectory = false
    guard fileManager.fileExists(at: directory, isDirectory: &isDirectory) else {
        return []
    }
    guard isDirectory else { return [directory] }

    let contents = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [])
    let files = try contents.flatMap { try flatFiles(in: $0) }
    return files
}

// MARK: - Data URL Utilities

struct DecodedDataURL {
    var mimeType: String
    var data: Data
}

/// Decode data from a data URL string.
///
/// Supports both `data:<mime>;base64,...` and valid non-base64 data URLs such
/// as `data:image/svg+xml;charset=utf-8,%3Csvg...`.
func decodeDataURL(_ dataURL: String) -> DecodedDataURL? {
    guard dataURL.hasPrefix("data:") else {
        return nil
    }

    let body = dataURL.dropFirst(5)
    guard let commaIndex = body.firstIndex(of: ",") else {
        return nil
    }

    let header = String(body[..<commaIndex])
    let payload = String(body[body.index(after: commaIndex)...])
    let headerParts = header.split(separator: ";", omittingEmptySubsequences: false)
        .map(String.init)
    let mimeType = headerParts.first?.nilIfBlank ?? "application/octet-stream"
    let isBase64 = headerParts.dropFirst().contains {
        $0.caseInsensitiveCompare("base64") == .orderedSame
    }

    let data: Data?
    if isBase64 {
        data = Data(base64Encoded: payload, options: [.ignoreUnknownCharacters])
    } else {
        data = (payload.removingPercentEncoding ?? payload).data(using: .utf8)
    }

    guard let data else { return nil }
    return DecodedDataURL(mimeType: mimeType, data: data)
}

/// Decode data from a data URL string.
///
/// Kept for older call sites that originally only accepted base64 data URLs.
func decodeBase64FromDataURL(_ dataURL: String) -> Data? {
    decodeDataURL(dataURL)?.data
}

/// Decode base64 data from a raw base64 string
/// - Parameter base64String: Pure base64 encoded string
/// - Returns: Decoded Data, or nil if decoding fails
func decodeBase64(_ base64String: String) -> Data? {
    return Data(base64Encoded: base64String, options: [.ignoreUnknownCharacters])
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
