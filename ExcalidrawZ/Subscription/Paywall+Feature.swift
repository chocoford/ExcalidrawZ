//
//  Paywall+Feature.swift
//  ExcalidrawZ
//
//  Created by Codex on 5/13/26.
//

import SwiftUI
import ChocofordUI
import SFSafeSymbols

extension Paywall {
    struct Feature: Identifiable, Hashable {
        let id: String
        let symbol: SFSymbol
        let title: String
        let subtitle: String
        let badge: String?

        var mcpServiceMode: ExcalidrawMCPServiceMode? {
            switch id {
                case Self.basicMCPServices.id:
                    .basic
                case Self.optimizedMCPServices.id:
                    .optimized
                default:
                    nil
            }
        }

        private init(
            id: String,
            symbol: SFSymbol,
            title: String,
            subtitle: String,
            badge: String? = nil
        ) {
            self.id = id
            self.symbol = symbol
            self.title = title
            self.subtitle = subtitle
            self.badge = badge
        }

        static let completeCanvasWorkspace = Feature(
            id: "complete-canvas-workspace",
            symbol: .pencilTipCropCircle,
            title: String(localizable: .paywallFeatureDrawTitle),
            subtitle: String(localizable: .paywallFeatureDrawMessage)
        )

        static let basicMCPServices = Feature(
            id: "basic-mcp-services",
            symbol: .serverRack,
            title: String(localizable: .paywallFeatureMCPTitle),
            subtitle: String(localizable: .paywallFeatureMCPMessage)
        )

        static let optimizedMCPServices = Feature(
            id: "optimized-mcp-services",
            symbol: .sparkles,
            title: String(localizable: .paywallFeatureOptimizedMCPTitle),
            subtitle: String(localizable: .paywallFeatureOptimizedMCPMessage)
        )

        static let unlimitedCollaborationTools = Feature(
            id: "unlimited-collaboration-tools",
            symbol: .person2Wave2,
            title: String(localizable: .paywallFeatureStarterCollaborationTitle),
            subtitle: String(localizable: .paywallFeatureStarterCollaborationMessage)
        )

        static let presentation = Feature(
            id: "presentation",
            symbol: .rectangleStack,
            title: String(localizable: .paywallFeaturePresentationTitle),
            subtitle: String(localizable: .paywallFeaturePresentationMessage)
        )

        static let proAICredits = Feature(
            id: "pro-ai-credits-500",
            symbol: .sparkles,
            title: String(localizable: .paywallFeatureAICreditsTitle(500)),
            subtitle: String(localizable: .paywallFeatureProAICreditsMessage)
        )

        static func maxAICredits(_ credits: Int) -> Feature {
            Feature(
                id: "max-ai-credits-\(credits)",
                symbol: .sparkles,
                title: String(localizable: .paywallFeatureAICreditsTitle(credits)),
                subtitle: String(localizable: .paywallFeatureMaxAICreditsMessage)
            )
        }

        static let extraHighModelCapability = Feature(
            id: "extra-high-model-capability",
            symbol: .brainHeadProfile,
            title: String(localizable: .paywallFeatureMaxExtraHighModelCapabilityTitle),
            subtitle: String(localizable: .paywallFeatureMaxExtraHighModelCapabilityMessage)
        )
    }
}
