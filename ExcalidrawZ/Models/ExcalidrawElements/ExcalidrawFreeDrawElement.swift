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
    var index: String?
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

    enum CodingKeys: String, CodingKey {
        case id
        case x
        case y
        case strokeColor
        case backgroundColor
        case fillStyle
        case strokeWidth
        case strokeStyle
        case roundness
        case roughness
        case opacity
        case width
        case height
        case angle
        case seed
        case version
        case versionNonce
        case index
        case isDeleted
        case groupIds
        case frameId
        case boundElements
        case updated
        case link
        case locked
        case customData
        case type
        case points
        case pressures
        case simulatePressure
        case lastCommittedPoint
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(String.self, forKey: .id)
        self.x = try container.decode(Double.self, forKey: .x)
        self.y = try container.decode(Double.self, forKey: .y)
        self.strokeColor = try container.decode(String.self, forKey: .strokeColor)
        self.backgroundColor = try container.decode(String.self, forKey: .backgroundColor)
        self.fillStyle = try container.decode(ExcalidrawFillStyle.self, forKey: .fillStyle)
        self.strokeWidth = try container.decode(Double.self, forKey: .strokeWidth)
        self.strokeStyle = try container.decode(ExcalidrawStrokeStyle.self, forKey: .strokeStyle)
        self.roundness = try container.decodeIfPresent(ExcalidrawRoundness.self, forKey: .roundness)
        self.roughness = try container.decode(Double.self, forKey: .roughness)
        self.opacity = try container.decode(Double.self, forKey: .opacity)
        self.width = try container.decode(Double.self, forKey: .width)
        self.height = try container.decode(Double.self, forKey: .height)
        self.angle = try container.decode(Double.self, forKey: .angle)
        self.seed = try container.decode(Int.self, forKey: .seed)
        self.version = try container.decode(Int.self, forKey: .version)
        self.versionNonce = try container.decode(Int.self, forKey: .versionNonce)
        self.index = try container.decodeIfPresent(String.self, forKey: .index)
        self.isDeleted = try container.decode(Bool.self, forKey: .isDeleted)
        self.groupIds = try container.decode([String].self, forKey: .groupIds)
        self.frameId = try container.decodeIfPresent(String.self, forKey: .frameId)
        self.boundElements = try container.decodeIfPresent([ExcalidrawBoundElement].self, forKey: .boundElements)
        self.updated = try container.decodeIfPresent(Double.self, forKey: .updated)
        self.link = try container.decodeIfPresent(String.self, forKey: .link)
        self.locked = try container.decodeIfPresent(Bool.self, forKey: .locked)
        self.customData = try container.decodeIfPresent([String : AnyCodable].self, forKey: .customData)
        self.type = try container.decode(ExcalidrawElementType.self, forKey: .type)
        self.points = try container.decode([Point].self, forKey: .points)
        self.pressures = try container.decodeIfPresent([Double].self, forKey: .pressures) ?? []
        let decodedSimulatePressure = try container.decodeIfPresent(Bool.self, forKey: .simulatePressure) ?? self.pressures.isEmpty
        self.simulatePressure = decodedSimulatePressure || self.pressures.isEmpty
        self.lastCommittedPoint = try container.decodeIfPresent(Point.self, forKey: .lastCommittedPoint)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(x, forKey: .x)
        try container.encode(y, forKey: .y)
        try container.encode(strokeColor, forKey: .strokeColor)
        try container.encode(backgroundColor, forKey: .backgroundColor)
        try container.encode(fillStyle, forKey: .fillStyle)
        try container.encode(strokeWidth, forKey: .strokeWidth)
        try container.encode(strokeStyle, forKey: .strokeStyle)
        if let roundness {
            try container.encode(roundness, forKey: .roundness)
        } else {
            try container.encodeNil(forKey: .roundness)
        }
        try container.encode(roughness, forKey: .roughness)
        try container.encode(opacity, forKey: .opacity)
        try container.encode(width, forKey: .width)
        try container.encode(height, forKey: .height)
        try container.encode(angle, forKey: .angle)
        try container.encode(seed, forKey: .seed)
        try container.encode(version, forKey: .version)
        try container.encode(versionNonce, forKey: .versionNonce)
        if let index {
            try container.encode(index, forKey: .index)
        } else {
            try container.encodeNil(forKey: .index)
        }
        try container.encode(isDeleted, forKey: .isDeleted)
        try container.encode(groupIds, forKey: .groupIds)
        if let frameId {
            try container.encode(frameId, forKey: .frameId)
        } else {
            try container.encodeNil(forKey: .frameId)
        }
        if let boundElements {
            try container.encode(boundElements, forKey: .boundElements)
        } else {
            try container.encodeNil(forKey: .boundElements)
        }
        try container.encodeIfPresent(updated, forKey: .updated)
        if let link {
            try container.encode(link, forKey: .link)
        } else {
            try container.encodeNil(forKey: .link)
        }
        try container.encodeIfPresent(locked, forKey: .locked)
        try container.encodeIfPresent(customData, forKey: .customData)
        try container.encode(type, forKey: .type)
        try container.encode(points, forKey: .points)
        try container.encode(pressures, forKey: .pressures)
        try container.encode(simulatePressure, forKey: .simulatePressure)
        if let lastCommittedPoint {
            try container.encode(lastCommittedPoint, forKey: .lastCommittedPoint)
        } else {
            try container.encodeNil(forKey: .lastCommittedPoint)
        }
    }
    
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
    var index: String?
    var isDeleted: Bool
    var groupIds: [String]
    var frameId: String?
    var boundElements: [ExcalidrawBoundElement]?
    var updated: Double? // not available in v1
    var link: String?
    var locked: Bool? // not available in v1
    var customData: [String : AnyCodable]?
    var type: ExcalidrawElementType

    enum CodingKeys: String, CodingKey {
        case id
        case x
        case y
        case strokeColor
        case backgroundColor
        case fillStyle
        case strokeWidth
        case strokeStyle
        case roundness
        case roughness
        case opacity
        case width
        case height
        case angle
        case seed
        case version
        case versionNonce
        case index
        case isDeleted
        case groupIds
        case frameId
        case boundElements
        case updated
        case link
        case locked
        case customData
        case type
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(x, forKey: .x)
        try container.encode(y, forKey: .y)
        try container.encode(strokeColor, forKey: .strokeColor)
        try container.encode(backgroundColor, forKey: .backgroundColor)
        try container.encode(fillStyle, forKey: .fillStyle)
        try container.encode(strokeWidth, forKey: .strokeWidth)
        try container.encode(strokeStyle, forKey: .strokeStyle)
        if let roundness {
            try container.encode(roundness, forKey: .roundness)
        } else {
            try container.encodeNil(forKey: .roundness)
        }
        try container.encode(roughness, forKey: .roughness)
        try container.encode(opacity, forKey: .opacity)
        try container.encode(width, forKey: .width)
        try container.encode(height, forKey: .height)
        try container.encode(angle, forKey: .angle)
        try container.encode(seed, forKey: .seed)
        try container.encode(version, forKey: .version)
        try container.encode(versionNonce, forKey: .versionNonce)
        if let index {
            try container.encode(index, forKey: .index)
        } else {
            try container.encodeNil(forKey: .index)
        }
        try container.encode(isDeleted, forKey: .isDeleted)
        try container.encode(groupIds, forKey: .groupIds)
        if let frameId {
            try container.encode(frameId, forKey: .frameId)
        } else {
            try container.encodeNil(forKey: .frameId)
        }
        if let boundElements {
            try container.encode(boundElements, forKey: .boundElements)
        } else {
            try container.encodeNil(forKey: .boundElements)
        }
        try container.encodeIfPresent(updated, forKey: .updated)
        if let link {
            try container.encode(link, forKey: .link)
        } else {
            try container.encodeNil(forKey: .link)
        }
        try container.encodeIfPresent(locked, forKey: .locked)
        try container.encodeIfPresent(customData, forKey: .customData)
        try container.encode(type, forKey: .type)
    }
    
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
