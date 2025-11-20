//
//  ExcalidrawBaseElement.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 2023/8/6.
//

import Foundation


enum ExcalidrawChartType: String, Codable {
    case bar
    case line
}

enum ExcalidrawFillStyle: String, Codable {
    case hachure
    case crossHatch = "cross-hatch"
    case solid
    case zigzag
}

enum ExcalidrawStrokeStyle: String, Codable {
    case solid
    case dashed
    case dotted
}


struct ExcalidrawRoundness: Codable, Hashable {
    var type: RoundnessType
    var value: Double?
    
    enum RoundnessType: Int, Codable {
        case legacy = 1
        case proportionalRadius = 2
        case adaptiveRadius = 3
    }

}

struct ExcalidrawBoundElement: Codable, Hashable {
    var id: String
    var type: BoundElementType
    
    enum BoundElementType: String, Codable {
        case text, arrow
    }
}

enum ExcalidrawElementType: String, Codable {
    case arrow = "arrow"
    case ellipse = "ellipse"
    case freedraw = "freedraw"
    case draw = "draw" // lagacy v1
    case line = "line"
    case rectangle = "rectangle"
    case text = "text"
    case selection = "selection"
    case diamond = "diamond"
    case image = "image"
    case pdf = "pdf"
    case frame = "frame"
    case magicFrame = "magicframe"
    case embeddable = "embeddable"
    case iframe = "iframe"
}

struct ExcalidrawBrand: Codable, Hashable {
    var _brand: String
}
enum ExcalidrawRadians: Codable, Hashable {
    case number(Double)
    case brand(ExcalidrawBrand)
}

enum FractionalIndex: Codable, Hashable {
    case string(String)
    case brand(ExcalidrawBrand)
}

protocol ExcalidrawElementBase: Codable, Identifiable, Hashable {
    var id: String { get }
    var x: Double { get }
    var y: Double { get }
    var strokeColor: String { get }
    var backgroundColor: String { get }
    var fillStyle: ExcalidrawFillStyle { get }
    var strokeWidth: Double { get }
    var strokeStyle: ExcalidrawStrokeStyle { get }
    var roundness: ExcalidrawRoundness? { get }
    var roughness: Double { get }
    var opacity: Double { get }
    var width: Double { get }
    var height: Double { get }
    var angle: Double { get }
    var seed: Int { get }
    var version: Int { get }
    var versionNonce: Int { get }
    var index: String? { get }
    var isDeleted: Bool { get }
    var groupIds: [String] { get }
    var frameId: String? { get }
    var boundElements: [ExcalidrawBoundElement]? { get }
    var updated: Double? { get } // not available in v1
    var link: String? { get }
    var locked: Bool? { get } // not available in v1
    var customData: [String: AnyCodable]? { get }
    
    var type: ExcalidrawElementType { get }
}


enum AnyCodable: Codable, Hashable, Sendable {
    case string(String)
    case bool(Bool)
    case int(Int)
    case double(Double)
    case strings([String])
    case dictinoary([String : AnyCodable])
    case dicArray([String : [AnyCodable]])
    case null
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let v = try? container.decode([String].self) {
            self = .strings(v)
            return
        }
        if let v = try? container.decode(String.self) {
            self = .string(v)
            return
        }
        if let v = try? container.decode(Int.self) {
            self = .int(v)
            return
        }
        if let v = try? container.decode(Double.self) {
            self = .double(v)
            return
        }
        if let v = try? container.decode(Bool.self) {
            self = .bool(v)
            return
        }
        if let v = try? container.decode([String : [AnyCodable]].self) {
            self = .dicArray(v)
            return
        }
        if let v = try? container.decode([String : AnyCodable].self) {
            self = .dictinoary(v)
            return
        }
        if container.decodeNil() {
            self = .null
            return
        }
        throw DecodingError.typeMismatch(
            AnyCodable.self,
            DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "[AnyCodable] Type is not matched", underlyingError: nil))
    }
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
            case .string(let value):
                try container.encode(value)
            case .strings(let value):
                try container.encode(value)
            case .int(let value):
                try container.encode(value)
            case .double(let value):
                try container.encode(value)
            case .bool(let value):
                try container.encode(value)
            case .dictinoary(let value):
                try container.encode(value)
            case .dicArray(let value):
                try container.encode(value)
            case .null:
                try container.encodeNil()
        }
    }
    
    public func decode<T: Codable>(to: T) throws -> T {
        let data = try JSONEncoder().encode(self)
        return try JSONDecoder().decode(T.self, from: data)
    }
}
