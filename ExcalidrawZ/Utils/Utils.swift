//
//  Utils.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 2022/12/26.
//

import Foundation
import SwiftUI
#if canImport(AppKit)
import AppKit
#endif

import WebKit

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
func archiveAllFiles(context: NSManagedObjectContext) throws {
    let panel = ExcalidrawOpenPanel.exportPanel
    if panel.runModal() == .OK {
        if let url = panel.url {
            let filemanager = FileManager.default
            do {
                let exportURL = url.appendingPathComponent("ExcalidrawZ exported at \(Date.now.formatted(date: .abbreviated, time: .shortened))", conformingTo: .directory)
                try filemanager.createDirectory(at: exportURL, withIntermediateDirectories: false)
                try archiveAllCloudFiles(to: exportURL, context: context)
            } catch {
                print(error)
                throw error
            }
        } else {
            throw AppError.fileError(.invalidURL)
        }
    }
}

func getBackupsDir() throws -> URL {
    let filemanager = FileManager.default
    let supportDir = try filemanager.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
    let backupsDir = supportDir.appendingPathComponent("backups", conformingTo: .directory)
    if !filemanager.fileExists(at: backupsDir) {
        try filemanager.createDirectory(at: backupsDir, withIntermediateDirectories: true)
    }
    return backupsDir
}

func backupFiles(context: NSManagedObjectContext) throws {
    let fileManager = FileManager.default
    let backupsDir = try getBackupsDir()
    
    let today = Date()
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd"
    let exportURL = backupsDir.appendingPathComponent(formatter.string(from: today), conformingTo: .directory)
    if fileManager.fileExists(at: exportURL) { return }

    
    // Cloud
    let cloudExportURL = exportURL.appendingPathComponent("Cloud", conformingTo: .directory)
    do {
        print("[Backup Files] Start... \(cloudExportURL)")
        try fileManager.createDirectory(at: cloudExportURL, withIntermediateDirectories: true)
        try archiveAllCloudFiles(to: cloudExportURL, context: context)
    } catch {
        print("[Backup Files] backup cloud files done, but with error: \(error)")
    }
    // Local
    let localExportURL = exportURL.appendingPathComponent("Local", conformingTo: .directory)
    Task {
        do {
            print("[Backup Files] Start... \(localExportURL)")
            try fileManager.createDirectory(at: localExportURL, withIntermediateDirectories: true)
            let context = PersistenceController.shared.container.newBackgroundContext()
            try await context.perform {
                let fetchRequest = NSFetchRequest<LocalFolder>(entityName: "LocalFolder")
                fetchRequest.predicate = NSPredicate(format: "parent = nil")
                let allFolders = try context.fetch(fetchRequest)
                
                for folder in allFolders {
                    try folder.withSecurityScopedURL { scopedURL in
                        let fileCoordinator = NSFileCoordinator()
                        fileCoordinator.coordinate(readingItemAt: scopedURL, error: nil) { url in
                            do {
                                try fileManager.copyItem(
                                    at: url,
                                    to: localExportURL.appendingPathComponent(url.lastPathComponent, conformingTo: .directory)
                                )
                            } catch {
                                print("[Backup Files] error occured when copy local folder: \(url)")
                            }
                        }
                    }
                }
            }
        } catch {
            print("[Backup Files] backup local files done, but with error: \(error)")
        }
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
    print("[Backup files] folder to keep: \(foldersToKeep.count), folder to delete: \(foldersToDelete.count)")
    for folder in foldersToDelete {
        do {
            try fileManager.removeItem(at: folder)
        } catch {
            print(error)
        }
    }
}

func archiveAllCloudFiles(to url: URL, context: NSManagedObjectContext) throws {
    let filemanager = FileManager.default
    let allFiles = try PersistenceController.shared.listAllFiles(context: context)
    print("Archive all files: \(allFiles.map {[$0.key : $0.value.map{$0.name}]}.merged())")
    
    var errorDuringArchive: Error?
    
    for files in allFiles {
        let dir = url.appendingPathComponent(files.key, conformingTo: .directory)
        try filemanager.createDirectory(at: dir, withIntermediateDirectories: false)
        for file in files.value {
            do {
                var file = try ExcalidrawFile(from: file)
                try file.syncFiles(context: PersistenceController.shared.container.viewContext)
                var index = 1
                var filename = file.name ?? String(localizable: .newFileNamePlaceholder)
                var fileURL: URL = dir.appendingPathComponent(filename, conformingTo: .fileURL).appendingPathExtension("excalidraw")
                var retryCount = 0
                while filemanager.fileExists(at: fileURL), retryCount < 100 {
                    if filename.hasSuffix(" (\(index))") {
                        filename = filename.replacingOccurrences(of: " (\(index))", with: "")
                        index += 1
                    }
                    filename = "\(filename) (\(index))"
                    fileURL = fileURL
                        .deletingLastPathComponent()
                        .appendingPathComponent(filename, conformingTo: .excalidrawFile)
                    retryCount += 1
                }
                let filePath: String = fileURL.filePath
                if !filemanager.createFile(atPath: filePath, contents: file.content) {
                    print("export file \(filePath) failed")
                }
            } catch {
                errorDuringArchive = error
            }
        }
    }
    
    if let errorDuringArchive {
        throw errorDuringArchive
    }
}

// MARK: Export PDF
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
        
        print("PDF saved to: \(pdfURL)")
        return pdfURL
    } catch {
        print("Failed to create PDF: \(error)")
        throw error
    }
}


#endif

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
    
    print(#function, "files: \(files)")
    return files
}
