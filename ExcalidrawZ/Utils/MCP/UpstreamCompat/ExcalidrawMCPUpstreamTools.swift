//
//  ExcalidrawMCPUpstreamTools.swift
//  ExcalidrawZ
//
//  Created by Codex on 2026/06/14.
//

import Foundation

struct ExcalidrawMCPTool: Sendable {
    let name: String
    let title: String
    let description: String
    let inputSchema: MCPJSONValue
    let annotations: [String: MCPJSONValue]
    let meta: [String: MCPJSONValue]

    init(
        name: String,
        title: String,
        description: String,
        inputSchema: MCPJSONValue,
        annotations: [String: MCPJSONValue] = [:],
        meta: [String: MCPJSONValue] = [:]
    ) {
        self.name = name
        self.title = title
        self.description = description
        self.inputSchema = inputSchema
        self.annotations = annotations
        self.meta = meta
    }

    var jsonValue: MCPJSONValue {
        var object: [String: MCPJSONValue] = [
            "name": .string(name),
            "title": .string(title),
            "description": .string(description),
            "inputSchema": inputSchema
        ]

        if !annotations.isEmpty {
            object["annotations"] = .object(annotations)
        }
        if !meta.isEmpty {
            object["_meta"] = .object(meta)
        }

        return .object(object)
    }
}

struct ExcalidrawMCPToolResult: Sendable {
    struct Content: Sendable {
        let type: String
        let text: String?
        let data: String?
        let mimeType: String?
        let resource: MCPJSONValue?

        static func text(_ text: String) -> Content {
            Content(type: "text", text: text, data: nil, mimeType: nil, resource: nil)
        }

        static func image(data: String, mimeType: String) -> Content {
            Content(type: "image", text: nil, data: data, mimeType: mimeType, resource: nil)
        }

        static func resource(uri: String, mimeType: String, blob: String) -> Content {
            Content(
                type: "resource",
                text: nil,
                data: nil,
                mimeType: nil,
                resource: .object([
                    "uri": .string(uri),
                    "mimeType": .string(mimeType),
                    "blob": .string(blob)
                ])
            )
        }

        var jsonValue: MCPJSONValue {
            var object: [String: MCPJSONValue] = [
                "type": .string(type)
            ]
            if let text {
                object["text"] = .string(text)
            }
            if let data {
                object["data"] = .string(data)
            }
            if let mimeType {
                object["mimeType"] = .string(mimeType)
            }
            if let resource {
                object["resource"] = resource
            }
            return .object(object)
        }
    }

    let content: [Content]
    let isError: Bool
    let structuredContent: MCPJSONValue?

    init(
        text: String,
        isError: Bool = false,
        structuredContent: MCPJSONValue? = nil
    ) {
        self.content = [.text(text)]
        self.isError = isError
        self.structuredContent = structuredContent
    }

    init(
        content: [Content],
        isError: Bool = false,
        structuredContent: MCPJSONValue? = nil
    ) {
        self.content = content
        self.isError = isError
        self.structuredContent = structuredContent
    }

    var jsonValue: MCPJSONValue {
        var object: [String: MCPJSONValue] = [
            "content": .array(content.map(\.jsonValue))
        ]
        if isError {
            object["isError"] = .bool(true)
        }
        if let structuredContent {
            object["structuredContent"] = structuredContent
        }
        return .object(object)
    }
}

enum ExcalidrawMCPToolSchemas {
    static let emptyObject: MCPJSONValue = .object([
        "type": .string("object"),
        "properties": .object([:]),
        "additionalProperties": .bool(false)
    ])

    static let createView: MCPJSONValue = .object([
        "type": .string("object"),
        "properties": .object([
            "elements": .object([
                "type": .string("string"),
                "description": .string(
                    "JSON array string of Excalidraw elements. Must be valid JSON — no comments, no trailing commas. Keep compact. Call read_me first for format reference."
                )
            ])
        ]),
        "required": .array([.string("elements")]),
        "additionalProperties": .bool(false)
    ])

    static let checkpointID: MCPJSONValue = .object([
        "type": .string("object"),
        "properties": .object([
            "id": .object([
                "type": .string("string")
            ])
        ]),
        "required": .array([.string("id")]),
        "additionalProperties": .bool(false)
    ])

    static let saveCheckpoint: MCPJSONValue = .object([
        "type": .string("object"),
        "properties": .object([
            "id": .object([
                "type": .string("string")
            ]),
            "data": .object([
                "type": .string("string")
            ])
        ]),
        "required": .array([
            .string("id"),
            .string("data")
        ]),
        "additionalProperties": .bool(false)
    ])

    static let appOnlyToolMeta: [String: MCPJSONValue] = [
        "ui": .object([
            "visibility": .array([.string("app")])
        ])
    ]
}

enum ExcalidrawMCPUpstreamToolCatalog {
    static let tools: [ExcalidrawMCPTool] = [
        ExcalidrawMCPTool(
            name: ExcalidrawMCPUpstreamContract.ToolName.readMe,
            title: "Read Excalidraw Drawing Guide",
            description: "Returns the Excalidraw element format reference with color palettes, examples, and tips. Call this BEFORE using create_view for the first time.",
            inputSchema: ExcalidrawMCPToolSchemas.emptyObject,
            annotations: ["readOnlyHint": .bool(true)]
        ),
        ExcalidrawMCPTool(
            name: ExcalidrawMCPUpstreamContract.ToolName.createView,
            title: "Draw Diagram",
            description: """
            Renders a hand-drawn diagram using Excalidraw elements.
            Elements stream in one by one with draw-on animations.
            Call read_me first to learn the element format.
            """,
            inputSchema: ExcalidrawMCPToolSchemas.createView,
            annotations: ["readOnlyHint": .bool(true)]
        ),
        ExcalidrawMCPTool(
            name: ExcalidrawMCPUpstreamContract.ToolName.saveCheckpoint,
            title: "Save Checkpoint",
            description: "Update checkpoint with user-edited state.",
            inputSchema: ExcalidrawMCPToolSchemas.saveCheckpoint,
            meta: ExcalidrawMCPToolSchemas.appOnlyToolMeta
        ),
        ExcalidrawMCPTool(
            name: ExcalidrawMCPUpstreamContract.ToolName.readCheckpoint,
            title: "Read Checkpoint",
            description: "Read checkpoint state for restore.",
            inputSchema: ExcalidrawMCPToolSchemas.checkpointID,
            meta: ExcalidrawMCPToolSchemas.appOnlyToolMeta
        )
    ]
}
