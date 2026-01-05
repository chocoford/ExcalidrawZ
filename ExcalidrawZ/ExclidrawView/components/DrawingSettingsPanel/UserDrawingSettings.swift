//
//  UserDrawingSettings.swift
//  ExcalidrawZ
//
//  Created by Claude on 2026/01/04.
//

import Foundation

/// User drawing settings for Excalidraw
struct UserDrawingSettings: Codable {
    var currentItemStrokeWidth: Double?
    var currentItemStrokeColor: String?
    var currentItemBackgroundColor: String?
    var currentItemStrokeStyle: ExcalidrawStrokeStyle?
    var currentItemFillStyle: ExcalidrawFillStyle?
    var currentItemRoughness: Double?
    var currentItemOpacity: Double?
    var currentItemFontFamily: Int?
    var currentItemFontSize: Double?
    var currentItemTextAlign: String?
    var currentItemRoundness: ExcalidrawStrokeSharpness?
    var currentItemArrowType: String?
    var currentItemStartArrowhead: String?
    var currentItemEndArrowhead: String?

    /// Convert to JSON string for JavaScript
    func toJSONString() -> String? {
        guard let data = try? JSONEncoder().encode(self),
              let jsonString = String(data: data, encoding: .utf8) else {
            return nil
        }
        return jsonString
    }

    /// Create from dictionary (from JavaScript message)
    static func from(dict: [String: Any]) -> UserDrawingSettings {
        var settings = UserDrawingSettings()
        settings.currentItemStrokeWidth = dict["currentItemStrokeWidth"] as? Double
        settings.currentItemStrokeColor = dict["currentItemStrokeColor"] as? String
        settings.currentItemBackgroundColor = dict["currentItemBackgroundColor"] as? String

        // Convert string to enum types
        if let strokeStyle = dict["currentItemStrokeStyle"] as? String {
            settings.currentItemStrokeStyle = ExcalidrawStrokeStyle(rawValue: strokeStyle)
        }
        if let fillStyle = dict["currentItemFillStyle"] as? String {
            settings.currentItemFillStyle = ExcalidrawFillStyle(rawValue: fillStyle)
        }

        settings.currentItemRoughness = dict["currentItemRoughness"] as? Double
        settings.currentItemOpacity = dict["currentItemOpacity"] as? Double
        settings.currentItemFontFamily = dict["currentItemFontFamily"] as? Int
        settings.currentItemFontSize = dict["currentItemFontSize"] as? Double
        settings.currentItemTextAlign = dict["currentItemTextAlign"] as? String
        if let roundness = dict["currentItemRoundness"] as? String {
            settings.currentItemRoundness = ExcalidrawStrokeSharpness(rawValue: roundness)
        }
        settings.currentItemArrowType = dict["currentItemArrowType"] as? String
        settings.currentItemStartArrowhead = dict["currentItemStartArrowhead"] as? String
        settings.currentItemEndArrowhead = dict["currentItemEndArrowhead"] as? String
        return settings
    }
}
