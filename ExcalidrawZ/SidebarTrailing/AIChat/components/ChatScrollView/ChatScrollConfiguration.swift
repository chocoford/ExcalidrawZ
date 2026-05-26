//
//  ChatScrollConfiguration.swift
//  ExcalidrawZ
//

enum ChatScrollBackend {
    case swiftUI
    case nativeSingleHost
    case nativeTable
    case nativeStack
}

enum ChatScrollAssistantRoundRowMode {
    case grouped
    case splitSettledRows
}

struct ChatScrollConfiguration {
    let backend: ChatScrollBackend
    let assistantRoundRowMode: ChatScrollAssistantRoundRowMode
    let usesMessageWindowing: Bool

    static var automatic: ChatScrollConfiguration {
        let backend = defaultBackend
        return ChatScrollConfiguration(
            backend: backend,
            assistantRoundRowMode: defaultAssistantRoundRowMode(for: backend),
            usesMessageWindowing: false
        )
    }

    private static var defaultBackend: ChatScrollBackend {
#if os(macOS)
#if DEBUG
        AIChatRenderDebug.useStackMessageListHost ? .nativeStack : .nativeTable
#else
        .nativeStack
#endif
#else
        .swiftUI
#endif
    }

    private static func defaultAssistantRoundRowMode(
        for backend: ChatScrollBackend
    ) -> ChatScrollAssistantRoundRowMode {
        switch backend {
            case .nativeTable:
                .splitSettledRows
            case .swiftUI,
                    .nativeSingleHost,
                    .nativeStack:
                .grouped
        }
    }
}
