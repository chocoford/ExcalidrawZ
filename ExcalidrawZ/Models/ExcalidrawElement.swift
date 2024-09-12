//
//  ExcalidrawElement.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 2023/8/6.
//

import Foundation

enum ExcalidrawElement: Codable, Hashable {
    case generic(ExcalidrawGenericElement)
    case text(ExcalidrawTextElement)
    case linear(ExcalidrawLinearElement)
    case freeDraw(ExcalidrawFreeDrawElement)
    case draw(ExcalidrawDrawElement) // lagacy - only existed in v1
    case image(ExcalidrawImageElement)
    
    enum CodingKeys: String, CodingKey {
       case type
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(ExcalidrawElementType.self, forKey: .type)
        
        switch type {
            case .selection, .rectangle, .diamond, .ellipse:
                self = .generic(try ExcalidrawGenericElement(from: decoder))
            case .text:
                self = .text(try ExcalidrawTextElement(from: decoder))
            case .line, .arrow:
                self = .linear(try ExcalidrawLinearElement(from: decoder))
            case .freedraw:
                self = .freeDraw(try ExcalidrawFreeDrawElement(from: decoder))
            case .draw:
                self = .draw(try ExcalidrawDrawElement(from: decoder))
            case .image:
                self = .image(try ExcalidrawImageElement(from: decoder))
                
//            default:
//                throw DecodingError.typeMismatch(
//                    ExcalidrawGenericElement.self,
//                    DecodingError.Context(
//                        codingPath: decoder.codingPath,
//                        debugDescription: "Type<\(type)> is not matched",
//                        underlyingError: nil)
//                )
        }
    }
    
    func encode(to encoder: Encoder) throws {
        switch self {
            case .generic(let excalidrawGenericElement):
                try excalidrawGenericElement.encode(to: encoder)
            case .text(let excalidrawTextElement):
                try excalidrawTextElement.encode(to: encoder)
            case .linear(let excalidrawLinearElement):
                try excalidrawLinearElement.encode(to: encoder)
            case .freeDraw(let excalidrawFreeDrawElement):
                try excalidrawFreeDrawElement.encode(to: encoder)
            case .draw(let excalidrawDrawElement):
                try excalidrawDrawElement.encode(to: encoder)
            case .image(let excalidrawImageElement):
                try excalidrawImageElement.encode(to: encoder)
        }
    }
}


extension ExcalidrawElement: Identifiable {
    var id: String {
        switch self {
            case .generic(let excalidrawGenericElement):
                excalidrawGenericElement.id
            case .text(let excalidrawTextElement):
                excalidrawTextElement.id
            case .linear(let excalidrawLinearElement):
                excalidrawLinearElement.id
            case .freeDraw(let excalidrawFreeDrawElement):
                excalidrawFreeDrawElement.id
            case .draw(let excalidrawDrawElement):
                excalidrawDrawElement.id
            case .image(let excalidrawImageElement):
                excalidrawImageElement.id
        }
    }
}

extension ExcalidrawElement {
    var x: Double {
        switch self {
            case .generic(let excalidrawGenericElement):
                excalidrawGenericElement.x
            case .text(let excalidrawTextElement):
                excalidrawTextElement.x
            case .linear(let excalidrawLinearElement):
                excalidrawLinearElement.x
            case .freeDraw(let excalidrawFreeDrawElement):
                excalidrawFreeDrawElement.x
            case .draw(let excalidrawDrawElement):
                excalidrawDrawElement.x
            case .image(let excalidrawImageElement):
                excalidrawImageElement.x
        }
    }
    
    var y: Double {
        switch self {
            case .generic(let excalidrawGenericElement):
                excalidrawGenericElement.y
            case .text(let excalidrawTextElement):
                excalidrawTextElement.y
            case .linear(let excalidrawLinearElement):
                excalidrawLinearElement.y
            case .freeDraw(let excalidrawFreeDrawElement):
                excalidrawFreeDrawElement.y
            case .draw(let excalidrawDrawElement):
                excalidrawDrawElement.y
            case .image(let excalidrawImageElement):
                excalidrawImageElement.y
        }
    }
    
    var width: Double {
        switch self {
            case .generic(let excalidrawGenericElement):
                excalidrawGenericElement.width
            case .text(let excalidrawTextElement):
                excalidrawTextElement.width
            case .linear(let excalidrawLinearElement):
                excalidrawLinearElement.width
            case .freeDraw(let excalidrawFreeDrawElement):
                excalidrawFreeDrawElement.width
            case .draw(let excalidrawDrawElement):
                excalidrawDrawElement.width
            case .image(let excalidrawImageElement):
                excalidrawImageElement.width
        }
    }
    
    var height: Double {
        switch self {
            case .generic(let excalidrawGenericElement):
                excalidrawGenericElement.height
            case .text(let excalidrawTextElement):
                excalidrawTextElement.height
            case .linear(let excalidrawLinearElement):
                excalidrawLinearElement.height
            case .freeDraw(let excalidrawFreeDrawElement):
                excalidrawFreeDrawElement.height
            case .draw(let excalidrawDrawElement):
                excalidrawDrawElement.height
            case .image(let excalidrawImageElement):
                excalidrawImageElement.height
        }
    }
}


