//
//  ExcalidrawZMCPServer.swift
//  ExcalidrawZ
//
//  Created by Codex on 2026/06/14.
//

import Foundation
import FlyingFox

final class ExcalidrawZMCPServer {
    static let defaultPort: UInt16 = 8490

    let port: UInt16
    let router: ExcalidrawMCPToolRouter

    private let server: HTTPServer
    private var didInstallRoutes = false

    init(
        port: UInt16 = ExcalidrawZMCPServer.defaultPort,
        router: ExcalidrawMCPToolRouter = ExcalidrawMCPToolRouter()
    ) {
        self.port = port
        self.router = router
        self.server = HTTPServer(port: port, logger: ExcalidrawServerLogger())
    }

    func start() async throws {
        await installRoutesIfNeeded()
        try await server.run()
    }

    func stop() async {
        await server.stop()
    }

    private func installRoutesIfNeeded() async {
        guard !didInstallRoutes else { return }
        didInstallRoutes = true

        let handler = ExcalidrawMCPHTTPHandler(router: router)
        await server.appendRoute("POST /mcp", to: handler)
        await server.appendRoute("GET /mcp") { _ in
            try Self.jsonResponse(
                .object([
                    "status": .string("ok"),
                    "name": .string("ExcalidrawZ MCP Server"),
                    "endpoint": .string("/mcp")
                ])
            )
        }
    }

    private static func jsonResponse(
        _ value: MCPJSONValue,
        statusCode: HTTPStatusCode = .ok
    ) throws -> HTTPResponse {
        let data = try value.mcpJSONData()
        return HTTPResponse(
            statusCode: statusCode,
            headers: HTTPHeaders([
                .contentType: "application/json; charset=utf-8"
            ]),
            body: data
        )
    }
}

private struct ExcalidrawMCPHTTPHandler: HTTPHandler {
    let router: ExcalidrawMCPToolRouter

    func handleRequest(_ request: HTTPRequest) async throws -> HTTPResponse {
        guard request.method == .POST else {
            return HTTPResponse(
                statusCode: .methodNotAllowed,
                headers: HTTPHeaders([.contentType: "text/plain; charset=utf-8"]),
                body: Data("Use POST /mcp for MCP JSON-RPC requests.".utf8)
            )
        }

        let requestData = try await request.bodyData
        let rpcRequest: MCPJSONRPCRequest
        do {
            rpcRequest = try JSONDecoder().decode(MCPJSONRPCRequest.self, from: requestData)
        } catch {
            let response = MCPJSONRPCResponse.failure(
                id: nil,
                error: .parseError("Invalid JSON-RPC request: \(error.localizedDescription)")
            )
            return try jsonRPCResponse(response, statusCode: .badRequest)
        }

        guard let response = await router.handle(rpcRequest) else {
            return HTTPResponse(statusCode: .noContent)
        }

        return try jsonRPCResponse(response)
    }

    private func jsonRPCResponse(
        _ response: MCPJSONRPCResponse,
        statusCode: HTTPStatusCode = .ok
    ) throws -> HTTPResponse {
        HTTPResponse(
            statusCode: statusCode,
            headers: HTTPHeaders([
                .contentType: "application/json; charset=utf-8"
            ]),
            body: try response.mcpJSONData()
        )
    }
}
