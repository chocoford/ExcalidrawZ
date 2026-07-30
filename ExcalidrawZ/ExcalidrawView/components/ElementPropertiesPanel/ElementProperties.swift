//
//  ElementProperties.swift
//  ExcalidrawZ
//
//  Created by Codex on 2026/07/25.
//

import Foundation

struct ElementProperties: Codable, Equatable {
    var strokeColor: String?
    var backgroundColor: String?
    var fillStyle: ExcalidrawFillStyle?
    var strokeWidthKey: StrokeWidthKey?
    var strokeVariability: StrokeVariability?
    var strokeStyle: ExcalidrawStrokeStyle?
    var roughness: Double?
    var opacity: Double?
    var fontFamily: FontFamily?
    var fontSize: Double?
    var textAlign: String?
    var roundness: ExcalidrawStrokeSharpness?
    var arrowType: UserDrawingSettings.ArrowType?
    var startArrowhead: Nullable<Arrowhead>?
    var endArrowhead: Nullable<Arrowhead>?

    var strokeWidth: Double? {
        strokeWidthKey?.strokeWidth
    }

    mutating func setStrokeWidth(_ value: Double) {
        strokeWidthKey = .init(strokeWidth: value)
    }

    enum StrokeWidthKey: String, Codable {
        case thin
        case medium
        case bold

        var strokeWidth: Double {
            switch self {
                case .thin: 1
                case .medium: 2
                case .bold: 4
            }
        }

        init?(strokeWidth: Double) {
            switch strokeWidth {
                case 1:
                    self = .thin
                case 2:
                    self = .medium
                case 4:
                    self = .bold
                default:
                    return nil
            }
        }
    }

    enum StrokeVariability: String, Codable {
        case constant
        case variable
    }

    enum FontFamily: Int, Codable {
        case handDrawn = 5
        case normal = 6
        case code = 8
    }

    enum Defaults {
        static let strokeColor = "#1e1e1e"
        static let backgroundColor = "transparent"
        static let strokeWidth: Double = 2
        static let strokeVariability: StrokeVariability = .constant
        static let strokeStyle: ExcalidrawStrokeStyle = .solid
        static let fillStyle: ExcalidrawFillStyle = .solid
        static let roughness: Double = 1
        static let opacity: Double = 100
        static let fontFamily: FontFamily = .handDrawn
        static let fontSize: Double = 20
        static let textAlign = "left"
        static let roundness: ExcalidrawStrokeSharpness = .round
        static let arrowType: UserDrawingSettings.ArrowType = .sharp
        static let startArrowhead: Nullable<Arrowhead> = .null
        static let endArrowhead: Nullable<Arrowhead> = .value(.arrow)
    }

    func changes(from previous: Self) -> Self {
        var result = Self()
        if strokeColor != previous.strokeColor {
            result.strokeColor = strokeColor
        }
        if backgroundColor != previous.backgroundColor {
            result.backgroundColor = backgroundColor
        }
        if fillStyle != previous.fillStyle {
            result.fillStyle = fillStyle
        }
        if strokeWidthKey != previous.strokeWidthKey {
            result.strokeWidthKey = strokeWidthKey
        }
        if strokeVariability != previous.strokeVariability {
            result.strokeVariability = strokeVariability
        }
        if strokeStyle != previous.strokeStyle {
            result.strokeStyle = strokeStyle
        }
        if roughness != previous.roughness {
            result.roughness = roughness
        }
        if opacity != previous.opacity {
            result.opacity = opacity
        }
        if fontFamily != previous.fontFamily {
            result.fontFamily = fontFamily
        }
        if fontSize != previous.fontSize {
            result.fontSize = fontSize
        }
        if textAlign != previous.textAlign {
            result.textAlign = textAlign
        }
        if roundness != previous.roundness {
            result.roundness = roundness
        }
        if arrowType != previous.arrowType {
            result.arrowType = arrowType
        }
        if startArrowhead != previous.startArrowhead {
            result.startArrowhead = startArrowhead
        }
        if endArrowhead != previous.endArrowhead {
            result.endArrowhead = endArrowhead
        }
        return result
    }

    func toJSONString() -> String? {
        guard let data = try? JSONEncoder().encode(self) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

enum ElementPropertiesContext: Hashable {
    case shape
    case shapeWithText
    case text
    case freedraw
    case arrow
    case arrowWithText
    case mixed
    case mixedWithText
    case media

    init(elementTypes: [String]) {
        let contexts = Set(elementTypes.map(Self.context(for:)))
        self = contexts.count == 1 ? contexts.first ?? .media : .mixed
    }

    func includingBoundText() -> Self {
        switch self {
            case .shape:
                .shapeWithText
            case .arrow:
                .arrowWithText
            case .text, .shapeWithText, .arrowWithText, .mixedWithText:
                self
            case .freedraw, .mixed, .media:
                .mixedWithText
        }
    }

    private static func context(for type: String) -> Self {
        switch type {
            case "rectangle", "diamond", "ellipse", "line":
                .shape
            case "text":
                .text
            case "freedraw":
                .freedraw
            case "arrow":
                .arrow
            default:
                .media
        }
    }
}
