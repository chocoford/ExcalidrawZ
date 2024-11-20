//
//  ExcalidrawFreeDrawElement.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 2023/8/6.
//

import Foundation

protocol ExcalidrawFreeDrawElementBase: ExcalidrawElementBase {
    var points: [Point] { get }
    var pressures: [Double] { get }
    var simulatePressure: Bool { get }
    var lastCommittedPoint: Point? { get }
}

struct ExcalidrawFreeDrawElement: ExcalidrawFreeDrawElementBase {
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
    var isDeleted: Bool
    var groupIds: [String]
    var frameId: String?
    var boundElements: [ExcalidrawBoundElement]?
    var updated: Double? // not available in v1
    var link: String?
    var locked: Bool? // not available in v1
    var customData: [String : AnyCodable]?
    var type: ExcalidrawElementType

    var points: [Point]
    var pressures: [Double]
    var simulatePressure: Bool
    var lastCommittedPoint: Point?
    
    static func == (lhs: Self, rhs: Self) -> Bool {
        return lhs.id == rhs.id &&
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
        lhs.type == rhs.type &&
        lhs.points == rhs.points &&
        lhs.pressures == rhs.pressures &&
        lhs.simulatePressure == rhs.simulatePressure &&
        lhs.lastCommittedPoint == rhs.lastCommittedPoint
    }
}
 

/// Lagacy - v1
struct ExcalidrawDrawElement: ExcalidrawElementBase {
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
    var isDeleted: Bool
    var groupIds: [String]
    var frameId: String?
    var boundElements: [ExcalidrawBoundElement]?
    var updated: Double? // not available in v1
    var link: String?
    var locked: Bool? // not available in v1
    var customData: [String : AnyCodable]?
    var type: ExcalidrawElementType
    
    static func == (lhs: Self, rhs: Self) -> Bool {
        return lhs.id == rhs.id &&
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
            lhs.type == rhs.type
    }
}
