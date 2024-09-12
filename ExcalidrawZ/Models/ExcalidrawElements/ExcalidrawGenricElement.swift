//
//  ExcalidrawGenricElement.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 2023/8/6.
//

import Foundation

struct ExcalidrawGenericElement: ExcalidrawElementBase {
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
    var isDeleted: Bool
    var groupIds: [String]
    var frameId: String?
    var boundElements: [ExcalidrawBoundElement]?
    var updated: Double? // not available in v1
    var link: String?
    var locked: Bool? // not available in v1
    var customData: [String : AnyCodable]?
}

//enum ExcalidrawGenericElement: Codable, Hashable {
//    case selection(ExcalidrawSelectionElement)
//    case rectangle(ExcalidrawRectangleElement)
//    case diamond(ExcalidrawDiamondElement)
//    case ellipse(ExcalidrawEllipseElement)
//    
//    enum CodingKeys: String, CodingKey {
//        case type
//    }
//    
//    init(from decoder: Decoder) throws {
//        let container = try decoder.container(keyedBy: CodingKeys.self)
//        let type = try container.decode(ExcalidrawElementType.self, forKey: .type)
//        switch type {
//            case .selection:
//                self = .selection(try ExcalidrawSelectionElement(from: decoder))
//            case .rectangle:
//                self = .rectangle(try ExcalidrawRectangleElement(from: decoder))
//            case .diamond:
//                self = .diamond(try ExcalidrawDiamondElement(from: decoder))
//            case .ellipse:
//                self = .ellipse(try ExcalidrawEllipseElement(from: decoder))
//            default:
//                throw DecodingError.typeMismatch(
//                    ExcalidrawGenericElement.self,
//                    DecodingError.Context(
//                        codingPath: decoder.codingPath,
//                        debugDescription: "Type is not matched, expect selection/rectangle/diamond/ellipse, got \(type)",
//                        underlyingError: nil)
//                )
//        }
//    }
//    
//    func encode(to encoder: Encoder) throws {
//        switch self {
//            case .selection(let excalidrawSelectionElement):
//                try excalidrawSelectionElement.encode(to: encoder)
//            case .rectangle(let excalidrawRectangleElement):
//                try excalidrawRectangleElement.encode(to: encoder)
//            case .diamond(let excalidrawDiamondElement):
//                try excalidrawDiamondElement.encode(to: encoder)
//            case .ellipse(let excalidrawEllipseElement):
//                try excalidrawEllipseElement.encode(to: encoder)
//        }
//    }
//}
//
//extension ExcalidrawGenericElement: Identifiable {
//    var id: String {
//        switch self {
//            case .diamond(let element):
//                element.id
//            case .selection(let element):
//                element.id
//            case .rectangle(let element):
//                element.id
//            case .ellipse(let element):
//                element.id
//        }
//    }
//}
//
//extension ExcalidrawGenericElement {
//    var x: Double {
//        switch self {
//            case .selection(let excalidrawSelectionElement):
//                excalidrawSelectionElement.x
//            case .rectangle(let excalidrawRectangleElement):
//                excalidrawRectangleElement.x
//            case .diamond(let excalidrawDiamondElement):
//                excalidrawDiamondElement.x
//            case .ellipse(let excalidrawEllipseElement):
//                excalidrawEllipseElement.x
//        }
//    }
//    
//    var y: Double {
//        switch self {
//            case .selection(let excalidrawSelectionElement):
//                excalidrawSelectionElement.y
//            case .rectangle(let excalidrawRectangleElement):
//                excalidrawRectangleElement.y
//            case .diamond(let excalidrawDiamondElement):
//                excalidrawDiamondElement.y
//            case .ellipse(let excalidrawEllipseElement):
//                excalidrawEllipseElement.y
//        }
//    }
//    
//    var width: Double {
//        switch self {
//            case .selection(let excalidrawSelectionElement):
//                excalidrawSelectionElement.width
//            case .rectangle(let excalidrawRectangleElement):
//                excalidrawRectangleElement.width
//            case .diamond(let excalidrawDiamondElement):
//                excalidrawDiamondElement.width
//            case .ellipse(let excalidrawEllipseElement):
//                excalidrawEllipseElement.width
//        }
//    }
//    
//    var height: Double {
//        switch self {
//            case .selection(let excalidrawSelectionElement):
//                excalidrawSelectionElement.height
//            case .rectangle(let excalidrawRectangleElement):
//                excalidrawRectangleElement.height
//            case .diamond(let excalidrawDiamondElement):
//                excalidrawDiamondElement.height
//            case .ellipse(let excalidrawEllipseElement):
//                excalidrawEllipseElement.height
//        }
//    }
//}


// MARK: - ExcalidrawSelectionElement
protocol ExcalidrawSelectionElementBase: ExcalidrawElementBase {}
extension ExcalidrawSelectionElementBase {
    var type: ExcalidrawElementType { .selection }
}

struct ExcalidrawSelectionElement: ExcalidrawSelectionElementBase {
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
}

// MARK: - ExcalidrawRectangleElement
protocol ExcalidrawRectangleElementBase: ExcalidrawElementBase {}
extension ExcalidrawRectangleElementBase {
    var type: ExcalidrawElementType { .rectangle }
}
struct ExcalidrawRectangleElement: ExcalidrawRectangleElementBase {
    
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
}

//MARK: - ExcalidrawDiamondElement
protocol ExcalidrawDiamondElementBase: ExcalidrawElementBase {}
extension ExcalidrawDiamondElementBase {
    var type: ExcalidrawElementType { .diamond }
}
struct ExcalidrawDiamondElement: ExcalidrawDiamondElementBase {
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
}

// MARK: - ExcalidrawEllipseElement
protocol ExcalidrawEllipseElementBase: ExcalidrawElementBase {}
extension ExcalidrawEllipseElementBase {
    var type: ExcalidrawElementType { .ellipse }
}
struct ExcalidrawEllipseElement: ExcalidrawEllipseElementBase {
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
}
