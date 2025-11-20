//
//  ExcalidrawElement.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 2023/8/6.
//


import Foundation

enum ExcalidrawElement: Codable, Hashable, Sendable {
    case generic(ExcalidrawGenericElement)
    case text(ExcalidrawTextElement)
    case linear(ExcalidrawLinearElement)
    case arrow(ExcalidrawArrowElement)
    case freeDraw(ExcalidrawFreeDrawElement)
    case draw(ExcalidrawDrawElement) // lagacy - only existed in v1
    case image(ExcalidrawImageElement)
    case pdf(ExcalidrawPdfElement)
    case frameLike(ExcalidrawFrameLikeElement)
    case iframeLike(ExcalidrawIframeLikeElement)
    
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
            case .line:
                self = .linear(try ExcalidrawLinearElement(from: decoder))
            case  .arrow:
                self = .arrow(try ExcalidrawArrowElement(from: decoder))
            case .freedraw:
                self = .freeDraw(try ExcalidrawFreeDrawElement(from: decoder))
            case .draw:
                self = .draw(try ExcalidrawDrawElement(from: decoder))
            case .image:
                self = .image(try ExcalidrawImageElement(from: decoder))
            case .pdf:
                self = .pdf(try ExcalidrawPdfElement(from: decoder))
            case .frame, .magicFrame:
                self = .frameLike(try ExcalidrawFrameLikeElement(from: decoder))
            case .iframe, .embeddable:
                self = .iframeLike(try ExcalidrawIframeLikeElement(from: decoder))
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
            case .arrow(let excalidrawArrowElement):
                try excalidrawArrowElement.encode(to: encoder)
            case .freeDraw(let excalidrawFreeDrawElement):
                try excalidrawFreeDrawElement.encode(to: encoder)
            case .draw(let excalidrawDrawElement):
                try excalidrawDrawElement.encode(to: encoder)
            case .image(let excalidrawImageElement):
                try excalidrawImageElement.encode(to: encoder)
            case .pdf(let excalidrawPdfElement):
                try excalidrawPdfElement.encode(to: encoder)
            case .frameLike(let excalidrawFrameElement):
                try excalidrawFrameElement.encode(to: encoder)
            case .iframeLike(let excalidrawIframeLikeElement):
                try excalidrawIframeLikeElement.encode(to: encoder)
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
            case .arrow(let excalidrawArrowElement):
                excalidrawArrowElement.id
            case .freeDraw(let excalidrawFreeDrawElement):
                excalidrawFreeDrawElement.id
            case .draw(let excalidrawDrawElement):
                excalidrawDrawElement.id
            case .image(let excalidrawImageElement):
                excalidrawImageElement.id
            case .pdf(let excalidrawPdfElement):
                excalidrawPdfElement.id
            case .frameLike(let excalidrawFrameElement):
                excalidrawFrameElement.id
            case .iframeLike(let excalidrawIframeLikeElement):
                excalidrawIframeLikeElement.id
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
            case .arrow(let excalidrawArrowElement):
                excalidrawArrowElement.x
            case .freeDraw(let excalidrawFreeDrawElement):
                excalidrawFreeDrawElement.x
            case .draw(let excalidrawDrawElement):
                excalidrawDrawElement.x
            case .image(let excalidrawImageElement):
                excalidrawImageElement.x
            case .pdf(let excalidrawPdfElement):
                excalidrawPdfElement.x
            case .frameLike(let excalidrawFrameElement):
                excalidrawFrameElement.x
            case .iframeLike(let excalidrawIframeLikeElement):
                excalidrawIframeLikeElement.x
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
            case .arrow(let excalidrawArrowElement):
                excalidrawArrowElement.y
            case .freeDraw(let excalidrawFreeDrawElement):
                excalidrawFreeDrawElement.y
            case .draw(let excalidrawDrawElement):
                excalidrawDrawElement.y
            case .image(let excalidrawImageElement):
                excalidrawImageElement.y
            case .pdf(let excalidrawPdfElement):
                excalidrawPdfElement.y
            case .frameLike(let excalidrawFrameElement):
                excalidrawFrameElement.y
            case .iframeLike(let excalidrawIframeLikeElement):
                excalidrawIframeLikeElement.y
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
            case .arrow(let excalidrawArrowElement):
                excalidrawArrowElement.width
            case .freeDraw(let excalidrawFreeDrawElement):
                excalidrawFreeDrawElement.width
            case .draw(let excalidrawDrawElement):
                excalidrawDrawElement.width
            case .image(let excalidrawImageElement):
                excalidrawImageElement.width
            case .pdf(let excalidrawPdfElement):
                excalidrawPdfElement.width
            case .frameLike(let excalidrawFrameElement):
                excalidrawFrameElement.width
            case .iframeLike(let excalidrawIframeLikeElement):
                excalidrawIframeLikeElement.width
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
            case .arrow(let excalidrawArrowElement):
                excalidrawArrowElement.height
            case .freeDraw(let excalidrawFreeDrawElement):
                excalidrawFreeDrawElement.height
            case .draw(let excalidrawDrawElement):
                excalidrawDrawElement.height
            case .image(let excalidrawImageElement):
                excalidrawImageElement.height
            case .pdf(let excalidrawPdfElement):
                excalidrawPdfElement.height
            case .frameLike(let excalidrawFrameElement):
                excalidrawFrameElement.height
            case .iframeLike(let excalidrawIframeLikeElement):
                excalidrawIframeLikeElement.height
        }
    }
}

