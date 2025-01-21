//
//  ToolState.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 2024/10/8.
//

import SwiftUI
import WebKit
import Combine
import os.log

enum ExcalidrawTool: Int, Hashable, CaseIterable {
    case eraser = 0
    case cursor = 1
    case rectangle = 2
    case diamond
    case ellipse
    case arrow
    case line
    case freedraw
    case text
    case image
    case laser
    
    case frame
    case webEmbed
    case magicFrame
    
    init?(from tool: ExcalidrawView.Coordinator.SetActiveToolMessage.SetActiveToolMessageData.Tool) {
        switch tool {
            case .selection:
                self = .cursor
            case .rectangle:
                self = .rectangle
            case .diamond:
                self = .diamond
            case .ellipse:
                self = .ellipse
            case .arrow:
                self = .arrow
            case .line:
                self = .line
            case .freedraw:
                self = .freedraw
            case .text:
                self = .text
            case .image:
                self = .image
            case .eraser:
                self = .eraser
            case .laser:
                self = .laser
            case .frame:
                self = .frame
            case .webEmbed:
                self = .webEmbed
            case .magicFrame:
                self = .magicFrame
            default:
                return nil
        }
    }
    
    var keyEquivalent: Character? {
        switch self {
            case .eraser:
                Character("e")
            case .cursor:
                Character("v")
            case .rectangle:
                Character("r")
            case .diamond:
                Character("d")
            case .ellipse:
                Character("o")
            case .arrow:
                Character("a")
            case .line:
                Character("l")
            case .freedraw:
                Character("p")
            case .text:
                Character("t")
            case .laser:
                Character("k")
            case .frame:
                Character("f")
            case .image, .webEmbed, .magicFrame:
                nil
        }
    }
    
    var localization: LocalizedStringKey {
        switch self {
            case .eraser:
                    .localizable(.toolbarEraser)
            case .cursor:
                    .localizable(.toolbarSelection)
            case .rectangle:
                    .localizable(.toolbarRectangle)
            case .diamond:
                    .localizable(.toolbarDiamond)
            case .ellipse:
                    .localizable(.toolbarEllipse)
            case .arrow:
                    .localizable(.toolbarArrow)
            case .line:
                    .localizable(.toolbarLine)
            case .freedraw:
                    .localizable(.toolbarDraw)
            case .text:
                    .localizable(.toolbarText)
            case .image:
                    .localizable(.toolbarInsertImage)
            case .laser:
                    .localizable(.toolbarLaser)
            case .webEmbed:
                    .localizable(.toolbarWebEmbed)
            case .frame:
                    .localizable(.toolbarFrame)
            case .magicFrame:
                    .localizable(.toolbarMagicFrame)
        }
    }
}

final class ToolState: ObservableObject {
    var excalidrawWebCoordinator: ExcalidrawView.Coordinator?

    @Published var activatedTool: ExcalidrawTool? = .cursor
    @Published var inDragMode: Bool = false
    
    @Published var inPenMode: Bool = false
}

