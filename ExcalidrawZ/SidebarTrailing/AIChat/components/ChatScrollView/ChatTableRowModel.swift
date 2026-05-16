//
//  ChatTableRowModel.swift
//  ExcalidrawZ
//

import Foundation

struct ChatTableRowModel: Identifiable {
    enum Kind {
        case hiddenHistory(hiddenGroupCount: Int, isLoading: Bool)
        case group(MessageGroup)
        case assistantItem(AssistantRoundTableItem)
        case assistantAction(AssistantRoundTableAction)
        case transientError(id: UUID, message: String)
    }

    let id: String
    let signature: String
    let kind: Kind
}
