#if os(macOS)
import Foundation

enum ScreenAnnotationSelectionProperties {
    static func bounds(for elements: [[String: Any]]) -> CGRect? {
        let rects = elements.compactMap { element -> CGRect? in
            guard let x = number(element["x"]),
                  let y = number(element["y"]),
                  let width = number(element["width"]),
                  let height = number(element["height"]) else {
                return nil
            }

            let rect = CGRect(x: x, y: y, width: width, height: height)
            guard let angle = number(element["angle"]), angle != 0 else {
                return rect
            }

            let center = CGPoint(x: rect.midX, y: rect.midY)
            let corners = [
                CGPoint(x: rect.minX, y: rect.minY),
                CGPoint(x: rect.maxX, y: rect.minY),
                CGPoint(x: rect.maxX, y: rect.maxY),
                CGPoint(x: rect.minX, y: rect.maxY),
            ].map { point in
                let dx = point.x - center.x
                let dy = point.y - center.y
                return CGPoint(
                    x: center.x + dx * cos(angle) - dy * sin(angle),
                    y: center.y + dx * sin(angle) + dy * cos(angle)
                )
            }

            let minX = corners.map(\.x).min() ?? rect.minX
            let maxX = corners.map(\.x).max() ?? rect.maxX
            let minY = corners.map(\.y).min() ?? rect.minY
            let maxY = corners.map(\.y).max() ?? rect.maxY
            return CGRect(
                x: minX,
                y: minY,
                width: maxX - minX,
                height: maxY - minY
            )
        }

        return rects.reduce(nil) { partial, rect in
            partial?.union(rect) ?? rect
        }
    }

    static func properties(from element: [String: Any]) -> ElementProperties {
        var properties = ElementProperties()
        let type = element["type"] as? String

        properties.strokeColor = element["strokeColor"] as? String
        properties.backgroundColor = element["backgroundColor"] as? String
        properties.strokeStyle = (element["strokeStyle"] as? String)
            .flatMap(ExcalidrawStrokeStyle.init(rawValue:))
        properties.fillStyle = (element["fillStyle"] as? String)
            .flatMap(ExcalidrawFillStyle.init(rawValue:))
        properties.roughness = number(element["roughness"])
        properties.opacity = number(element["opacity"])

        if let strokeWidth = number(element["strokeWidth"]) {
            let normalizedWidth = type == "freedraw" ? strokeWidth * 2 : strokeWidth
            properties.strokeWidthKey = .init(strokeWidth: normalizedWidth)
        }

        if let strokeOptions = element["strokeOptions"] as? [String: Any],
           let variability = strokeOptions["variability"] as? String {
            properties.strokeVariability = .init(rawValue: variability)
        }

        if type == "text" {
            if let fontFamily = integer(element["fontFamily"]) {
                properties.fontFamily = .init(rawValue: fontFamily)
            }
            properties.fontSize = number(element["fontSize"])
            properties.textAlign = element["textAlign"] as? String
        }

        if type != "freedraw", type != "text" {
            properties.roundness = element["roundness"] is NSNull
                || element["roundness"] == nil ? .sharp : .round
        }

        if type == "arrow" {
            if let isElbowed = element["elbowed"] as? Bool, isElbowed {
                properties.arrowType = .elbow
            } else {
                properties.arrowType = properties.roundness == .round
                    ? .round
                    : .sharp
            }
            properties.startArrowhead = nullableArrowhead(
                element["startArrowhead"]
            )
            properties.endArrowhead = nullableArrowhead(
                element["endArrowhead"]
            )
        }

        return properties
    }

    static func boundTextElementIDs(
        from elements: [[String: Any]]
    ) -> [String] {
        elements.flatMap { element in
            guard let boundElements = element["boundElements"]
                as? [[String: Any]] else {
                return [String]()
            }
            return boundElements.compactMap { boundElement in
                guard boundElement["type"] as? String == "text" else {
                    return nil
                }
                return boundElement["id"] as? String
            }
        }
    }

    static func number(_ value: Any?) -> Double? {
        switch value {
            case let value as Double:
                value
            case let value as Int:
                Double(value)
            case let value as NSNumber:
                value.doubleValue
            default:
                nil
        }
    }

    private static func integer(_ value: Any?) -> Int? {
        switch value {
            case let value as Int:
                value
            case let value as NSNumber:
                value.intValue
            default:
                nil
        }
    }

    private static func nullableArrowhead(_ value: Any?) -> Nullable<Arrowhead> {
        guard !(value is NSNull),
              let rawValue = value as? String,
              let arrowhead = Arrowhead(rawValue: rawValue) else {
            return .null
        }
        return .value(arrowhead)
    }
}
#endif
