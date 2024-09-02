//
//  ExcalidrawImageElement.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 2023/8/6.
//

import Foundation
enum ExcalidrawImageElementStatus: String, Codable {
    case pending, saved, error
}

protocol ExcalidrawImageElementBase: ExcalidrawElementBase {
    var fileId: String? { get }
    var status: ExcalidrawImageElementStatus { get }
    var scale: [Double] { get }
}

extension ExcalidrawImageElementBase {
    var type: ExcalidrawElementType { .image }
}
 
struct ExcalidrawImageElement: ExcalidrawImageElementBase {
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
    
    var fileId: String?
    var status: ExcalidrawImageElementStatus
    var scale: [Double]
}
