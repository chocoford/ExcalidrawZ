//
//  ExcalidrawLinearElement.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 2023/8/6.
//

import Foundation
import CoreGraphics

typealias Point = CGPoint
extension CGPoint : Hashable {
  public func hash(into hasher: inout Hasher) {
    hasher.combine(x)
    hasher.combine(y)
  }
}

struct PointBinding: Codable, Hashable {
    var elementID: String
    var focus: Double
    var gap: Double
    
    enum CodingKeys: String, CodingKey {
        case elementID = "elementId"
        case focus
        case gap
    }
}

enum Arrowhead: String, Codable {
    case arrow
    case bar
    case dot
    case triangle
}

protocol ExcalidrawLinearElementBase: ExcalidrawElementBase {
    var points: [Point] { get }
    var lastCommittedPoint: Point? { get }
    var startBinding: PointBinding? { get }
    var endBinding: PointBinding? { get }
    var startArrowhead: Arrowhead? { get }
    var endArrowhead: Arrowhead? { get }
}

struct ExcalidrawLinearElement: ExcalidrawLinearElementBase {
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
    var lastCommittedPoint: Point?
    var startBinding: PointBinding?
    var endBinding: PointBinding?
    var startArrowhead: Arrowhead?
    var endArrowhead: Arrowhead?
    
    /// ignore `version`, `versionNounce`, `updated`
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
            lhs.lastCommittedPoint == rhs.lastCommittedPoint &&
            lhs.startBinding == rhs.startBinding &&
            lhs.endBinding == rhs.endBinding &&
            lhs.startArrowhead == rhs.startArrowhead &&
            lhs.endArrowhead == rhs.endArrowhead
    }
}
