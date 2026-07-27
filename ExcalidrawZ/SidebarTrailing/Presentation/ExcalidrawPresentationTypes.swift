//
//  ExcalidrawPresentationTypes.swift
//  ExcalidrawZ
//
//  Created by Codex on 2026/7/27.
//

import Foundation

struct ExcalidrawPresentationSlide: Identifiable {
    let id: String
    let title: String
    var isHidden: Bool
    var transition: ExcalidrawPresentationConfiguration.Transition
    var transitionDuration: TimeInterval
    var speakerNotes: String
    var image: PlatformImage?
}

struct ExcalidrawPresentationSession: Identifiable {
    let id = UUID()
    let title: String
    let slides: [ExcalidrawPresentationSlide]
    let initialSlideID: String?
}
