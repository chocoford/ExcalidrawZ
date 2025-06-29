//
//  ExcalidrawTextElement.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 2023/8/6.
//

import Foundation

enum TextAlign: String, Codable {
    case left, right, center
}

enum VerticalAlign: String, Codable {
    case top, bottom, middle
}

enum FontFamily: Codable, Hashable {
    case int(Int)
    case name(String)
    
    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let intValue = try? container.decode(Int.self) {
            self = .int(intValue)
        } else {
            let stringValue = try container.decode(String.self)
            self = .name(stringValue)
        }
    }
    
    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
            case .int(let value):
                try container.encode(value)
            case .name(let value):
                try container.encode(value)
        }
    }
}

protocol ExcalidrawTextElementBase: ExcalidrawElementBase {
    var fontSize: Double { get }
    var fontFamily: FontFamily { get }
    var text: String { get }
    var textAlign: TextAlign { get }
    var verticalAlign: VerticalAlign { get }
    var containerId: ExcalidrawGenericElement.ID? { get }
    var originalText: String? { get }
    /**
     * Unitless line height (aligned to W3C). To get line height in px, multiply
     * with font size (using `getLineHeightInPx` helper).
     */
    var lineHeight: Double? { get }
}
//extension ExcalidrawTextElementBase {
//    var type: ExcalidrawElementType { .text }
//}

struct ExcalidrawTextElement: ExcalidrawTextElementBase {
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
    
    var fontSize: Double
    var fontFamily: FontFamily// Int
    var text: String
    var textAlign: TextAlign
    var verticalAlign: VerticalAlign
    var containerId: ExcalidrawGenericElement.ID?
    var originalText: String?
    var autoResize: Bool
    var lineHeight: Double?

    
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
        lhs.fontSize == rhs.fontSize &&
        lhs.fontFamily == rhs.fontFamily &&
        lhs.text == rhs.text &&
        lhs.textAlign == rhs.textAlign &&
        lhs.verticalAlign == rhs.verticalAlign &&
        lhs.containerId == rhs.containerId &&
        lhs.originalText == rhs.originalText &&
        lhs.autoResize == rhs.autoResize &&
        lhs.lineHeight == rhs.lineHeight
    }
    
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.type = try container.decode(ExcalidrawElementType.self, forKey: .type)
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
        self.fontSize = try container.decode(Double.self, forKey: .fontSize)
        self.fontFamily = try container.decode(FontFamily.self, forKey: .fontFamily)
        self.text = try container.decode(String.self, forKey: .text)
        self.textAlign = try container.decode(TextAlign.self, forKey: .textAlign)
        self.verticalAlign = try container.decode(VerticalAlign.self, forKey: .verticalAlign)
        self.containerId = try container.decodeIfPresent(ExcalidrawGenericElement.ID.self, forKey: .containerId)
        self.originalText = try container.decodeIfPresent(String.self, forKey: .originalText)
        self.autoResize = try container.decodeIfPresent(Bool.self, forKey: .autoResize) ?? true
        self.lineHeight = try container.decodeIfPresent(Double.self, forKey: .lineHeight)
    }
}
