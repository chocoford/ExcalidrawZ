//
//  ExcalidrawImageElement.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 2023/8/6.
//

import Foundation
enum ExcalidrawImageElementStatus: String, Codable {
    case pending, saved, error
}

struct ExcalidrawIImageCrop: Codable, Hashable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double
    var naturalWidth: Double
    var naturalHeight: Double
}

protocol ExcalidrawImageElementBase: ExcalidrawElementBase {
    var fileId: String? { get }
    var status: ExcalidrawImageElementStatus { get }
    var scale: [Double] { get }
    var crop: ExcalidrawIImageCrop? { get }
}
 
struct ExcalidrawImageElement: ExcalidrawImageElementBase {
    var type: ExcalidrawElementType
    
    var id: String
    var x: Double
    var y: Double
    var strokeColor: String
    var backgroundColor: String
    var fillStyle: ExcalidrawFillStyle
    var strokeWidth: Double
    var strokeStyle: ExcalidrawStrokeStyle
    var roundness: ExcalidrawRoundness?
    var roughness: Double
    var opacity: Double
    var width: Double
    var height: Double
    var angle: Double
    var seed: Int
    var version: Int
    var versionNonce: Int
    var index: String?
    var isDeleted: Bool
    var groupIds: [String]
    var frameId: String?
    var boundElements: [ExcalidrawBoundElement]?
    var updated: Double? // not available in v1
    var link: String?
    var locked: Bool? // not available in v1
    var customData: [String : AnyCodable]?
    
    var fileId: String?
    var status: ExcalidrawImageElementStatus
    var scale: [Double]
    var crop: ExcalidrawIImageCrop?
    
    static func == (lhs: Self, rhs: Self) -> Bool {
        return lhs.type == rhs.type &&
        lhs.id == rhs.id &&
        lhs.x == rhs.x &&
        lhs.y == rhs.y &&
        lhs.strokeColor == rhs.strokeColor &&
        lhs.backgroundColor == rhs.backgroundColor &&
        lhs.fillStyle == rhs.fillStyle &&
        lhs.strokeWidth == rhs.strokeWidth &&
        lhs.strokeStyle == rhs.strokeStyle &&
        lhs.roundness == rhs.roundness &&
        lhs.roughness == rhs.roughness &&
        lhs.opacity == rhs.opacity &&
        lhs.width == rhs.width &&
        lhs.height == rhs.height &&
        lhs.angle == rhs.angle &&
        lhs.seed == rhs.seed &&
        lhs.isDeleted == rhs.isDeleted &&
        lhs.groupIds == rhs.groupIds &&
        lhs.frameId == rhs.frameId &&
        lhs.boundElements == rhs.boundElements &&
        lhs.link == rhs.link &&
        lhs.locked == rhs.locked &&
        lhs.customData == rhs.customData &&
        lhs.fileId == rhs.fileId &&
        lhs.status == rhs.status &&
        lhs.scale == rhs.scale
    }
    

}
