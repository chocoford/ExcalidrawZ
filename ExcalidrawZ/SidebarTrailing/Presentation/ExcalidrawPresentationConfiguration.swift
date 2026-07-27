//
//  ExcalidrawPresentationConfiguration.swift
//  ExcalidrawZ
//
//  Created by Codex on 2026/7/27.
//

import Foundation

/// App-owned presentation metadata stored alongside a managed Excalidraw file.
///
/// Keeping this separate from the Excalidraw document prevents presentation
/// edits from dirtying the canvas or creating checkpoints. The order of
/// `pages` is the presentation order; each page is bound to a frame by ID.
struct ExcalidrawPresentationConfiguration: Codable, Equatable, Sendable {
    static let currentVersion = 1

    var version: Int
    var pages: [Page]

    init(
        version: Int = Self.currentVersion,
        pages: [Page] = []
    ) {
        self.version = version
        self.pages = pages
    }

    /// Preserves configured page order and settings, removes stale frames, and
    /// appends newly created frames in their current scene order.
    func reconciled(withFrameIDs frameIDs: [String]) -> Self {
        let availableFrameIDs = Set(frameIDs)
        var includedFrameIDs = Set<String>()
        var reconciledPages: [Page] = []

        for page in pages
        where availableFrameIDs.contains(page.frameID)
            && includedFrameIDs.insert(page.frameID).inserted {
            reconciledPages.append(page)
        }

        for frameID in frameIDs where includedFrameIDs.insert(frameID).inserted {
            reconciledPages.append(Page(frameID: frameID))
        }

        return Self(
            version: Self.currentVersion,
            pages: reconciledPages
        )
    }

    struct Page: Codable, Equatable, Identifiable, Sendable {
        var frameID: String
        var isHidden: Bool
        /// The transition used when entering this page.
        var transition: Transition
        var transitionDuration: TimeInterval
        var speakerNotes: String

        var id: String {
            frameID
        }

        init(
            frameID: String,
            isHidden: Bool = false,
            transition: Transition = .none,
            transitionDuration: TimeInterval = 0.3,
            speakerNotes: String = ""
        ) {
            self.frameID = frameID
            self.isHidden = isHidden
            self.transition = transition
            self.transitionDuration = transitionDuration
            self.speakerNotes = speakerNotes
        }

        private enum CodingKeys: String, CodingKey {
            case frameID
            case isHidden
            case transition
            // Kept as a decode-only bridge for configurations created during
            // early Presentation development.
            case transitionAfter
            case transitionDuration
            case speakerNotes
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            frameID = try container.decode(String.self, forKey: .frameID)
            isHidden = try container.decodeIfPresent(Bool.self, forKey: .isHidden) ?? false
            transition = try container.decodeIfPresent(
                Transition.self,
                forKey: .transition
            ) ?? container.decodeIfPresent(
                Transition.self,
                forKey: .transitionAfter
            ) ?? .none
            transitionDuration = try container.decodeIfPresent(
                TimeInterval.self,
                forKey: .transitionDuration
            ) ?? 0.3
            speakerNotes = try container.decodeIfPresent(
                String.self,
                forKey: .speakerNotes
            ) ?? ""
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(frameID, forKey: .frameID)
            try container.encode(isHidden, forKey: .isHidden)
            try container.encode(transition, forKey: .transition)
            try container.encode(
                transitionDuration,
                forKey: .transitionDuration
            )
            try container.encode(speakerNotes, forKey: .speakerNotes)
        }
    }

    enum Transition: String, Codable, CaseIterable, Equatable, Hashable, Sendable {
        case none
        case fade
        case slide
        case zoom

        init(from decoder: Decoder) throws {
            let rawValue = try decoder.singleValueContainer().decode(String.self)
            self = Self(rawValue: rawValue) ?? .none
        }
    }

    private enum CodingKeys: String, CodingKey {
        case version
        case pages
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decodeIfPresent(Int.self, forKey: .version) ?? 1
        pages = try container.decodeIfPresent([Page].self, forKey: .pages) ?? []
    }
}
