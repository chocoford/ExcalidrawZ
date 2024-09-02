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
    var updated: Double
    var link: String?
    var locked: Bool
    var customData: [String : AnyCodable]?
    var type: ExcalidrawElementType

    var points: [Point]
    var lastCommittedPoint: Point?
    var startBinding: PointBinding?
    var endBinding: PointBinding?
    var startArrowhead: Arrowhead?
    var endArrowhead: Arrowhead?
    
}
