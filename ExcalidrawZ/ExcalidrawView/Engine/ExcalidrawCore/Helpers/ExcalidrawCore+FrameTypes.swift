//
//  ExcalidrawCore+FrameTypes.swift
//  ExcalidrawZ
//
//  Created by Codex on 2026/07/30.
//

import Foundation

extension ExcalidrawCore {
    struct CreateFrameFromElementsParams: Codable {
        var elementIds: [String]
        var name: String?
        var padding: Double?
        var captureUpdate: CaptureUpdate?
    }

    struct SetElementsFrameParams: Codable {
        var elementIds: [String]
        var frameId: Nullable<String>
        var captureUpdate: CaptureUpdate?
    }

    struct FrameMutationResult: Codable, Hashable {
        var frameId: String?
        var elementIds: [String]
        var bounds: MermaidBounds?
    }
}
