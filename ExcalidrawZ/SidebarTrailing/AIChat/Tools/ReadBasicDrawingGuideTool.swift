import Foundation
import LLMCore

struct ReadBasicDrawingGuideTool: Tool {
    var name: String { "read_me" }
    var displayName: String { String(localizable: .aIDirectDrawingGuide) }
    var description: String { "Read the local Basic MCP Excalidraw element guide before drawing." }
    var inputSchema: ToolInputSchema { .parameters(ToolParameters(properties: [:], required: [])) }

    func execute(_ input: String, context: (any ChatInvocationContext)?) async throws -> ToolResult {
        try AIChatToolExecutionGate.ensureAIEnabled()
        return .text("""
        In this in-app assistant, use the available native `adjust_elements` tool to insert elements:
        {"ops":[{"op":"add","elements":[...Excalidraw skeletons...]}]}
        The MCP reference below calls this `create_view`; use `adjust_elements` here instead.
        Use native edit/delete/navigation tools rather than MCP-only cameraUpdate, delete or restoreCheckpoint pseudo-elements.

        \(ExcalidrawMCPBasicReadMeStore.currentReadMe)
        """)
    }
}
