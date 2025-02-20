//
//  ExcalidrawIframeLikeElement.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 1/19/25.
//

import Foundation

struct ExcalidrawIframeLikeElement: ExcalidrawElementBase {
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
    
    // var customData: CustomData?
    
    struct CustomData: Codable, Hashable {
        var generationData: MagicGenerationData?
    }
    
    enum MagicGenerationData: Codable, Hashable {
        case pending(PendingData)
        case done(DoneData)
        case error(ErrorData)
        
        enum CodingKeys: String, CodingKey {
            case status
        }
        
        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let status = try container.decode(Status.self, forKey: .status)
            
            switch status {
                case .pending:
                    self = try .pending(PendingData(from: decoder))
                case .done:
                    self = try .done(DoneData(from: decoder))
                case .error:
                    self = try .error(ErrorData(from: decoder))
            }
        }
        
        func encode(to encoder: any Encoder) throws {
            switch self {
                case .pending(let pendingData):
                    try pendingData.encode(to: encoder)
                case .done(let doneData):
                    try doneData.encode(to: encoder)
                case .error(let errorData):
                    try errorData.encode(to: encoder)
            }
        }
        
        enum Status: String, Codable, Hashable {
            case pending, done, error
        }
        
        struct PendingData: Codable, Hashable {
            var status: Status
        }
        struct DoneData: Codable, Hashable {
            var status: Status
            var html: String
        }
        struct ErrorData: Codable, Hashable {
            var status: Status
            var message: String?
            var code: String
        }
    }
}
