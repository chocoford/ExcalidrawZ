//
//  ReadFileTool.swift
//  ExcalidrawZ
//
//  Created by Codex
//

import Foundation
import LLMCore


/// Tool to simplify the current Excalidraw file for AI consumption.
struct ReadFileTool: Tool {
    struct ReadFileContext: ToolContext {
        var currentFileData: Data?
        var selectedElementIDs: [String]?
    }

    var name: String { "read_file" }
    
    var description: String {
        "Read the current Excalidraw file."
    }
    
    var inputSchema: ToolInputSchema {
        .parameters(ToolParameters(properties: [:], required: []))
    }
    
    func execute(_ input: String, context: (any ChatInvocationContext)?) async throws -> ToolResult {
        let _ = input
        guard let context else { throw ToolError.executionFailed("Missing ReadFileContext") }
        let readFileContext = try context.resolve(ReadFileContext.self)
        guard let data = readFileContext.currentFileData else {
            throw ToolError.executionFailed("Missing current file data")
        }

        let decoder = JSONDecoder()
        let (elements, files, version, type, source) = try decodeExcalidrawPayload(data, decoder: decoder)

        let simplified = simplify(
            elements: elements,
            files: files,
            version: version,
            type: type,
            source: source,
            selectedElementIDs: readFileContext.selectedElementIDs,
            includeFiles: false,
            includeDeleted: false,
            maxElements: 200,
            maxPoints: 50
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let output = try encoder.encode(simplified)
        return .text(String(data: output, encoding: .utf8) ?? "")
    }
}

private extension ReadFileTool {
    
    func decodeExcalidrawPayload(
        _ data: Data,
        decoder: JSONDecoder
    ) throws -> ([ExcalidrawElement], [String: ExcalidrawFile.ResourceFile]?, Int?, String?, String?) {
        if let file = try? decoder.decode(ExcalidrawFile.self, from: data) {
            return (file.elements, file.files, file.version, file.type, file.source)
        }
        
        if let partial = try? decoder.decode(PartialExcalidrawFile.self, from: data) {
            return (
                partial.elements ?? [],
                partial.files,
                partial.version,
                partial.type,
                partial.source
            )
        }
        
        throw ToolError.executionFailed("Invalid Excalidraw file data.")
    }
    
    struct PartialExcalidrawFile: Decodable {
        var source: String?
        var files: [String: ExcalidrawFile.ResourceFile]?
        var version: Int?
        var elements: [ExcalidrawElement]?
        var type: String?
    }
    
    func simplify(
        elements: [ExcalidrawElement],
        files: [String: ExcalidrawFile.ResourceFile]?,
        version: Int?,
        type: String?,
        source: String?,
        selectedElementIDs: [String]?,
        includeFiles: Bool,
        includeDeleted: Bool,
        maxElements: Int,
        maxPoints: Int
    ) -> SimplifiedFile {
        let filteredElements = includeDeleted
        ? elements
        : elements.filter { !isDeleted($0) }
        
        let totalElements = filteredElements.count
        let elementLimit = maxElements <= 0 ? totalElements : maxElements
        let truncated = totalElements > elementLimit
        let visibleElements = truncated ? Array(filteredElements.prefix(elementLimit)) : filteredElements
        
        let simplifiedElements = visibleElements.map {
            simplifyElement($0, maxPoints: maxPoints)
        }
        
        let simplifiedFiles: [SimplifiedResourceFile]? = includeFiles
        ? files?.values.map { SimplifiedResourceFile(from: $0) }
        : nil
        
        return SimplifiedFile(
            source: source,
            type: type,
            version: version,
            selectedElementIDs: selectedElementIDs,
            totalElements: totalElements,
            includedElements: simplifiedElements.count,
            truncatedElements: truncated ? totalElements - simplifiedElements.count : nil,
            elements: simplifiedElements,
            files: simplifiedFiles
        )
    }
}

private extension ReadFileTool {
    struct SimplifiedFile: Codable {
        let source: String?
        let type: String?
        let version: Int?
        let selectedElementIDs: [String]?
        let totalElements: Int
        let includedElements: Int
        let truncatedElements: Int?
        let elements: [SimplifiedElement]
        let files: [SimplifiedResourceFile]?
    }
    
    struct SimplifiedResourceFile: Codable {
        let id: String
        let mimeType: String
        let createdAt: Date?
        let lastRetrievedAt: Date?
        
        init(from file: ExcalidrawFile.ResourceFile) {
            self.id = file.id
            self.mimeType = file.mimeType
            self.createdAt = file.createdAt
            self.lastRetrievedAt = file.lastRetrievedAt
        }
    }
    
    struct Bounds: Codable {
        let x: Double
        let y: Double
        let width: Double
        let height: Double
    }
    
    struct SimplePoint: Codable {
        let x: Double
        let y: Double
    }
    
    struct SimplifiedBinding: Codable {
        let kind: String
        let elementId: String?
        let fixedPoint: [Double]?
        let mode: String?
        let focus: Double?
        let gap: Double?
    }
    
    struct SimplifiedSegment: Codable {
        let index: Int
        let start: SimplePoint
        let end: SimplePoint
    }
    
    struct SimplifiedCrop: Codable {
        let x: Double
        let y: Double
        let width: Double
        let height: Double
        let naturalWidth: Double
        let naturalHeight: Double
    }
    
    struct SimplifiedElement: Codable {
        let id: String
        let type: String
        let bounds: Bounds
        let isDeleted: Bool
        let groupIds: [String]?
        let frameId: String?
        let link: String?
        
        let text: String?
        let originalText: String?
        let containerId: String?
        
        let points: [SimplePoint]?
        let pointCount: Int?
        let pointsTruncated: Bool?
        
        let startBinding: SimplifiedBinding?
        let endBinding: SimplifiedBinding?
        let startArrowhead: String?
        let endArrowhead: String?
        let elbowed: Bool?
        let fixedSegments: [SimplifiedSegment]?
        let startIsSpecial: Bool?
        let endIsSpecial: Bool?
        
        let fileId: String?
        let status: String?
        let crop: SimplifiedCrop?
        let currentPage: Int?
        let totalPages: Int?
        let name: String?
    }
    
    func simplifyElement(_ element: ExcalidrawElement, maxPoints: Int) -> SimplifiedElement {
        let base = baseInfo(for: element)
        let pointLimit = maxPoints <= 0 ? nil : maxPoints
        
        switch element {
            case .generic(_):
                return SimplifiedElement(
                    id: base.id,
                    type: base.type,
                    bounds: base.bounds,
                    isDeleted: base.isDeleted,
                    groupIds: base.groupIds,
                    frameId: base.frameId,
                    link: base.link,
                    text: nil,
                    originalText: nil,
                    containerId: nil,
                    points: nil,
                    pointCount: nil,
                    pointsTruncated: nil,
                    startBinding: nil,
                    endBinding: nil,
                    startArrowhead: nil,
                    endArrowhead: nil,
                    elbowed: nil,
                    fixedSegments: nil,
                    startIsSpecial: nil,
                    endIsSpecial: nil,
                    fileId: nil,
                    status: nil,
                    crop: nil,
                    currentPage: nil,
                    totalPages: nil,
                    name: nil
                )
            case .text(let item):
                return SimplifiedElement(
                    id: base.id,
                    type: base.type,
                    bounds: base.bounds,
                    isDeleted: base.isDeleted,
                    groupIds: base.groupIds,
                    frameId: base.frameId,
                    link: base.link,
                    text: item.text,
                    originalText: item.originalText,
                    containerId: item.containerId,
                    points: nil,
                    pointCount: nil,
                    pointsTruncated: nil,
                    startBinding: nil,
                    endBinding: nil,
                    startArrowhead: nil,
                    endArrowhead: nil,
                    elbowed: nil,
                    fixedSegments: nil,
                    startIsSpecial: nil,
                    endIsSpecial: nil,
                    fileId: nil,
                    status: nil,
                    crop: nil,
                    currentPage: nil,
                    totalPages: nil,
                    name: nil
                )
            case .linear(let item):
                let pointInfo = simplifyPoints(item.points, maxPoints: pointLimit)
                return SimplifiedElement(
                    id: base.id,
                    type: base.type,
                    bounds: base.bounds,
                    isDeleted: base.isDeleted,
                    groupIds: base.groupIds,
                    frameId: base.frameId,
                    link: base.link,
                    text: nil,
                    originalText: nil,
                    containerId: nil,
                    points: pointInfo.points,
                    pointCount: pointInfo.totalCount,
                    pointsTruncated: pointInfo.truncated,
                    startBinding: simplifyBinding(item.startBinding),
                    endBinding: simplifyBinding(item.endBinding),
                    startArrowhead: item.startArrowhead?.rawValue,
                    endArrowhead: item.endArrowhead?.rawValue,
                    elbowed: nil,
                    fixedSegments: nil,
                    startIsSpecial: nil,
                    endIsSpecial: nil,
                    fileId: nil,
                    status: nil,
                    crop: nil,
                    currentPage: nil,
                    totalPages: nil,
                    name: nil
                )
            case .arrow(let item):
                let pointInfo = simplifyPoints(item.points, maxPoints: pointLimit)
                return SimplifiedElement(
                    id: base.id,
                    type: base.type,
                    bounds: base.bounds,
                    isDeleted: base.isDeleted,
                    groupIds: base.groupIds,
                    frameId: base.frameId,
                    link: base.link,
                    text: nil,
                    originalText: nil,
                    containerId: nil,
                    points: pointInfo.points,
                    pointCount: pointInfo.totalCount,
                    pointsTruncated: pointInfo.truncated,
                    startBinding: simplifyBinding(item.startBinding),
                    endBinding: simplifyBinding(item.endBinding),
                    startArrowhead: item.startArrowhead?.rawValue,
                    endArrowhead: item.endArrowhead?.rawValue,
                    elbowed: item.elbowed,
                    fixedSegments: simplifySegments(item.fixedSegments),
                    startIsSpecial: item.startIsSpecial,
                    endIsSpecial: item.endIsSpecial,
                    fileId: nil,
                    status: nil,
                    crop: nil,
                    currentPage: nil,
                    totalPages: nil,
                    name: nil
                )
            case .freeDraw(let item):
                let pointInfo = simplifyPoints(item.points, maxPoints: pointLimit)
                return SimplifiedElement(
                    id: base.id,
                    type: base.type,
                    bounds: base.bounds,
                    isDeleted: base.isDeleted,
                    groupIds: base.groupIds,
                    frameId: base.frameId,
                    link: base.link,
                    text: nil,
                    originalText: nil,
                    containerId: nil,
                    points: pointInfo.points,
                    pointCount: pointInfo.totalCount,
                    pointsTruncated: pointInfo.truncated,
                    startBinding: nil,
                    endBinding: nil,
                    startArrowhead: nil,
                    endArrowhead: nil,
                    elbowed: nil,
                    fixedSegments: nil,
                    startIsSpecial: nil,
                    endIsSpecial: nil,
                    fileId: nil,
                    status: nil,
                    crop: nil,
                    currentPage: nil,
                    totalPages: nil,
                    name: nil
                )
            case .draw(_):
                return SimplifiedElement(
                    id: base.id,
                    type: base.type,
                    bounds: base.bounds,
                    isDeleted: base.isDeleted,
                    groupIds: base.groupIds,
                    frameId: base.frameId,
                    link: base.link,
                    text: nil,
                    originalText: nil,
                    containerId: nil,
                    points: nil,
                    pointCount: nil,
                    pointsTruncated: nil,
                    startBinding: nil,
                    endBinding: nil,
                    startArrowhead: nil,
                    endArrowhead: nil,
                    elbowed: nil,
                    fixedSegments: nil,
                    startIsSpecial: nil,
                    endIsSpecial: nil,
                    fileId: nil,
                    status: nil,
                    crop: nil,
                    currentPage: nil,
                    totalPages: nil,
                    name: nil
                )
            case .image(let item):
                return SimplifiedElement(
                    id: base.id,
                    type: base.type,
                    bounds: base.bounds,
                    isDeleted: base.isDeleted,
                    groupIds: base.groupIds,
                    frameId: base.frameId,
                    link: base.link,
                    text: nil,
                    originalText: nil,
                    containerId: nil,
                    points: nil,
                    pointCount: nil,
                    pointsTruncated: nil,
                    startBinding: nil,
                    endBinding: nil,
                    startArrowhead: nil,
                    endArrowhead: nil,
                    elbowed: nil,
                    fixedSegments: nil,
                    startIsSpecial: nil,
                    endIsSpecial: nil,
                    fileId: item.fileId,
                    status: item.status.rawValue,
                    crop: simplifyCrop(item.crop),
                    currentPage: nil,
                    totalPages: nil,
                    name: nil
                )
            case .pdf(let item):
                return SimplifiedElement(
                    id: base.id,
                    type: base.type,
                    bounds: base.bounds,
                    isDeleted: base.isDeleted,
                    groupIds: base.groupIds,
                    frameId: base.frameId,
                    link: base.link,
                    text: nil,
                    originalText: nil,
                    containerId: nil,
                    points: nil,
                    pointCount: nil,
                    pointsTruncated: nil,
                    startBinding: nil,
                    endBinding: nil,
                    startArrowhead: nil,
                    endArrowhead: nil,
                    elbowed: nil,
                    fixedSegments: nil,
                    startIsSpecial: nil,
                    endIsSpecial: nil,
                    fileId: item.fileId,
                    status: item.status.rawValue,
                    crop: nil,
                    currentPage: item.currentPage,
                    totalPages: item.totalPages,
                    name: nil
                )
            case .frameLike(let item):
                return SimplifiedElement(
                    id: base.id,
                    type: base.type,
                    bounds: base.bounds,
                    isDeleted: base.isDeleted,
                    groupIds: base.groupIds,
                    frameId: base.frameId,
                    link: base.link,
                    text: nil,
                    originalText: nil,
                    containerId: nil,
                    points: nil,
                    pointCount: nil,
                    pointsTruncated: nil,
                    startBinding: nil,
                    endBinding: nil,
                    startArrowhead: nil,
                    endArrowhead: nil,
                    elbowed: nil,
                    fixedSegments: nil,
                    startIsSpecial: nil,
                    endIsSpecial: nil,
                    fileId: nil,
                    status: nil,
                    crop: nil,
                    currentPage: nil,
                    totalPages: nil,
                    name: item.name
                )
            case .iframeLike:
                return SimplifiedElement(
                    id: base.id,
                    type: base.type,
                    bounds: base.bounds,
                    isDeleted: base.isDeleted,
                    groupIds: base.groupIds,
                    frameId: base.frameId,
                    link: base.link,
                    text: nil,
                    originalText: nil,
                    containerId: nil,
                    points: nil,
                    pointCount: nil,
                    pointsTruncated: nil,
                    startBinding: nil,
                    endBinding: nil,
                    startArrowhead: nil,
                    endArrowhead: nil,
                    elbowed: nil,
                    fixedSegments: nil,
                    startIsSpecial: nil,
                    endIsSpecial: nil,
                    fileId: nil,
                    status: nil,
                    crop: nil,
                    currentPage: nil,
                    totalPages: nil,
                    name: nil
                )
        }
    }
    
    struct BaseInfo {
        let id: String
        let type: String
        let bounds: Bounds
        let isDeleted: Bool
        let groupIds: [String]?
        let frameId: String?
        let link: String?
    }
    
    func baseInfo(for element: ExcalidrawElement) -> BaseInfo {
        switch element {
            case .generic(let item):
                return BaseInfo(
                    id: item.id,
                    type: item.type.rawValue,
                    bounds: Bounds(x: item.x, y: item.y, width: item.width, height: item.height),
                    isDeleted: item.isDeleted,
                    groupIds: item.groupIds.isEmpty ? nil : item.groupIds,
                    frameId: item.frameId,
                    link: item.link
                )
            case .text(let item):
                return BaseInfo(
                    id: item.id,
                    type: item.type.rawValue,
                    bounds: Bounds(x: item.x, y: item.y, width: item.width, height: item.height),
                    isDeleted: item.isDeleted,
                    groupIds: item.groupIds.isEmpty ? nil : item.groupIds,
                    frameId: item.frameId,
                    link: item.link
                )
            case .linear(let item):
                return BaseInfo(
                    id: item.id,
                    type: item.type.rawValue,
                    bounds: Bounds(x: item.x, y: item.y, width: item.width, height: item.height),
                    isDeleted: item.isDeleted,
                    groupIds: item.groupIds.isEmpty ? nil : item.groupIds,
                    frameId: item.frameId,
                    link: item.link
                )
            case .arrow(let item):
                return BaseInfo(
                    id: item.id,
                    type: item.type.rawValue,
                    bounds: Bounds(x: item.x, y: item.y, width: item.width, height: item.height),
                    isDeleted: item.isDeleted,
                    groupIds: item.groupIds.isEmpty ? nil : item.groupIds,
                    frameId: item.frameId,
                    link: item.link
                )
            case .freeDraw(let item):
                return BaseInfo(
                    id: item.id,
                    type: item.type.rawValue,
                    bounds: Bounds(x: item.x, y: item.y, width: item.width, height: item.height),
                    isDeleted: item.isDeleted,
                    groupIds: item.groupIds.isEmpty ? nil : item.groupIds,
                    frameId: item.frameId,
                    link: item.link
                )
            case .draw(let item):
                return BaseInfo(
                    id: item.id,
                    type: item.type.rawValue,
                    bounds: Bounds(x: item.x, y: item.y, width: item.width, height: item.height),
                    isDeleted: item.isDeleted,
                    groupIds: item.groupIds.isEmpty ? nil : item.groupIds,
                    frameId: item.frameId,
                    link: item.link
                )
            case .image(let item):
                return BaseInfo(
                    id: item.id,
                    type: item.type.rawValue,
                    bounds: Bounds(x: item.x, y: item.y, width: item.width, height: item.height),
                    isDeleted: item.isDeleted,
                    groupIds: item.groupIds.isEmpty ? nil : item.groupIds,
                    frameId: item.frameId,
                    link: item.link
                )
            case .pdf(let item):
                return BaseInfo(
                    id: item.id,
                    type: item.type.rawValue,
                    bounds: Bounds(x: item.x, y: item.y, width: item.width, height: item.height),
                    isDeleted: item.isDeleted,
                    groupIds: item.groupIds.isEmpty ? nil : item.groupIds,
                    frameId: item.frameId,
                    link: item.link
                )
            case .frameLike(let item):
                return BaseInfo(
                    id: item.id,
                    type: item.type.rawValue,
                    bounds: Bounds(x: item.x, y: item.y, width: item.width, height: item.height),
                    isDeleted: item.isDeleted,
                    groupIds: item.groupIds.isEmpty ? nil : item.groupIds,
                    frameId: item.frameId,
                    link: item.link
                )
            case .iframeLike(let item):
                return BaseInfo(
                    id: item.id,
                    type: item.type.rawValue,
                    bounds: Bounds(x: item.x, y: item.y, width: item.width, height: item.height),
                    isDeleted: item.isDeleted,
                    groupIds: item.groupIds.isEmpty ? nil : item.groupIds,
                    frameId: item.frameId,
                    link: item.link
                )
        }
    }
    
    func isDeleted(_ element: ExcalidrawElement) -> Bool {
        switch element {
            case .generic(let item): return item.isDeleted
            case .text(let item): return item.isDeleted
            case .linear(let item): return item.isDeleted
            case .arrow(let item): return item.isDeleted
            case .freeDraw(let item): return item.isDeleted
            case .draw(let item): return item.isDeleted
            case .image(let item): return item.isDeleted
            case .pdf(let item): return item.isDeleted
            case .frameLike(let item): return item.isDeleted
            case .iframeLike(let item): return item.isDeleted
        }
    }
    
    func simplifyPoints(_ points: [Point], maxPoints: Int?) -> (points: [SimplePoint]?, totalCount: Int?, truncated: Bool?) {
        let total = points.count
        let limit = maxPoints ?? total
        let truncated = total > limit
        let visible = truncated ? points.prefix(limit) : points[0..<points.count]
        let simplified = visible.map { SimplePoint(x: Double($0.x), y: Double($0.y)) }
        return (
            points: simplified.isEmpty ? nil : simplified,
            totalCount: total,
            truncated: truncated ? true : nil
        )
    }
    
    func simplifyBinding(_ binding: PointBinding?) -> SimplifiedBinding? {
        guard let binding else { return nil }
        switch binding {
            case .fixed(let fixed):
                return SimplifiedBinding(
                    kind: "fixed",
                    elementId: fixed.elementID,
                    fixedPoint: fixed.fixedPoint,
                    mode: fixed.mode.rawValue,
                    focus: nil,
                    gap: nil
                )
            case .lagacy(let legacy):
                return SimplifiedBinding(
                    kind: "legacy",
                    elementId: legacy.elementID,
                    fixedPoint: nil,
                    mode: nil,
                    focus: legacy.focus,
                    gap: legacy.gap
                )
        }
    }
    
    func simplifySegments(_ segments: [FixedSegment]?) -> [SimplifiedSegment]? {
        guard let segments else { return nil }
        return segments.enumerated().map { (i, segement) in
            SimplifiedSegment(
                index: i,
                start: SimplePoint(x: Double(segement.start.x), y: Double(segement.start.y)),
                end: SimplePoint(x: Double(segement.end.x), y: Double(segement.end.y))
            )
        }
    }
    
    func simplifyCrop(_ crop: ExcalidrawIImageCrop?) -> SimplifiedCrop? {
        guard let crop else { return nil }
        return SimplifiedCrop(
            x: crop.x,
            y: crop.y,
            width: crop.width,
            height: crop.height,
            naturalWidth: crop.naturalWidth,
            naturalHeight: crop.naturalHeight
        )
    }
}
