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

import SFSafeSymbols

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
    
    case hand
    
    // extra tool
//    case text2Diagram
//    case mermaid
    
    
    init?(
        from tool: ExcalidrawView.Coordinator.SetActiveToolMessage.SetActiveToolMessageData.Tool
    ) {
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
                
            case .hand:
                self = .hand
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
            case .image:
                Character("9")
            case .hand:
                Character("h")
            case .webEmbed, .magicFrame/*, .text2Diagram, .mermaid*/:
                nil
        }
    }
    
    var localization: LocalizedStringKey {
        switch self {
            case .hand:
                    .localizable(.toolbarHand)
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

//            case .text2Diagram:
//                    .localizable(.toolbarText2Diagram)
//            case .mermaid:
//                    .localizable(.toolbarMermaid)
        }
    }
    
    var help: String {
        switch self {
            case .eraser:
                "\(String(localizable: .toolbarEraser)) — E \(String(localizable: .toolbarOr)) 0"
            case .cursor:
                "\(String(localizable: .toolbarSelection)) - V \(String(localizable: .toolbarOr)) 1"
            case .rectangle:
                "\(String(localizable: .toolbarRectangle)) — R \(String(localizable: .toolbarOr)) 2"
            case .diamond:
                "\(String(localizable: .toolbarDiamond)) — D \(String(localizable: .toolbarOr)) 3"
            case .ellipse:
                "\(String(localizable: .toolbarEllipse)) — O \(String(localizable: .toolbarOr)) 4"
            case .arrow:
                "\(String(localizable: .toolbarArrow)) — A \(String(localizable: .toolbarOr)) 5"
            case .line:
                "\(String(localizable: .toolbarLine)) — L \(String(localizable: .toolbarOr)) 6"
            case .freedraw:
                "\(String(localizable: .toolbarDraw)) — P \(String(localizable: .toolbarOr)) 7"
            case .text:
                "\(String(localizable: .toolbarText)) — T \(String(localizable: .toolbarOr)) 8"
            case .image:
                "\(String(localizable: .toolbarInsertImage)) — 9"
            case .laser:
                "\(String(localizable: .toolbarLaser)) — K"
            case .frame:
                "\(String(localizable: .toolbarFrame)) - F"
            case .webEmbed:
                "\(String(localizable: .toolbarWebEmbed))"
            case .magicFrame:
                "\(String(localizable: .toolbarMagicFrame))"
            case .hand:
                "\(String(localizable: .toolbarHand)) - H"
        }
    }
    
    @MainActor @ViewBuilder
    public func icon(strokeLineWidth: CGFloat = 1.5) -> some View {
        switch self {
            case .eraser:
                if #available(macOS 13.0, *) {
                    Image(systemSymbol: .eraserLineDashed)
                        .resizable()
                        .scaledToFit()
                        .font(.body.weight(.semibold))
                } else {
                    Image(systemSymbol: .pencilSlash)
                        .resizable()
                        .scaledToFit()
                        .font(.body.weight(.semibold))
                }
            case .cursor:
                Image(systemSymbol: .cursorarrow)
                    .resizable()
                    .scaledToFit()
                    .font(.body.weight(.semibold))

            case .rectangle:
                RoundedRectangle(cornerRadius: 3)
                    .stroke(.primary, lineWidth: strokeLineWidth)
                    .padding(1)
            case .diamond:
                RoundedRectangle(cornerRadius: 3)
                    .stroke(.primary, lineWidth: strokeLineWidth)
                    .rotationEffect(.degrees(45))
                    .padding(2)
            case .ellipse:
                Circle()
                    .stroke(.primary, lineWidth: strokeLineWidth)
            case .arrow:
                Image(systemSymbol: .arrowRight)
                    .resizable()
                    .scaledToFit()
                    .font(.body.weight(.semibold))
            case .line:
                Capsule()
                    .stroke(.primary, lineWidth: strokeLineWidth)
                    .frame(height: 1)
            case .freedraw:
                Image(systemSymbol: .pencil)
                    .resizable()
                    .scaledToFit()
                    .font(.body.weight(.semibold))
            case .text:
                Image(systemSymbol: .character)
                    .resizable()
                    .scaledToFit()
                    .font(.body.weight(.semibold))
            case .image:
                Image(systemSymbol: .photo)
                    .resizable()
                    .scaledToFit()
                    .font(.body.weight(.semibold))
            case .laser:
                Image(systemSymbol: .cursorarrowRays)
                    .resizable()
                    .scaledToFit()
                    .font(.body.weight(.semibold))
            case .frame:
                Image(systemSymbol: .grid)
                    .resizable()
                    .scaledToFit()
                    .font(.body.weight(.semibold))
            case .webEmbed:
                Image(systemSymbol: .chevronLeftForwardslashChevronRight)
                    .resizable()
                    .scaledToFit()
                    .font(.body.weight(.semibold))
            case .magicFrame:
                Image(systemSymbol: .wandAndStarsInverse)
                    .resizable()
                    .scaledToFit()
                    .font(.body.weight(.semibold))
            case .hand:
                Image(systemSymbol: .handRaised)
                    .resizable()
                    .scaledToFit()
                    .font(.body.weight(.semibold))
//            case .text2Diagram, .mermaid:
//                EmptyView()
        }
    }
}

final class ToolState: ObservableObject {
    let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "ToolState")
    var excalidrawWebCoordinator: ExcalidrawView.Coordinator?
    // var excalidrawCollaborationWebCoordinator: ExcalidrawView.Coordinator?

    @Published var activatedTool: ExcalidrawTool? = .cursor
    @Published var isToolLocked: Bool = false
    @Published var previousActivatedTool: ExcalidrawTool? = nil
    @Published var inDragMode: Bool = false
    
    @Published var inPenMode: Bool = false
    
    @Published var isActionsMenuPresneted = true
    @Published var isBottomBarPresented = true
    
    enum PencilInteractionMode: Int, Hashable {
        case fingerSelect = 0
        case fingerMove
    }

    @AppStorage("PencilInteractionMode") var pencilInteractionMode: PencilInteractionMode = .fingerSelect
    
    func toggleTool(_ tool: ExcalidrawTool) async throws {
        logger.info("Toggle tool: \(String(describing: tool))")
        switch tool {
            case .webEmbed:
                try await self.excalidrawWebCoordinator?.toggleToolbarAction(tool: .webEmbed)
            case .magicFrame:
                try await self.excalidrawWebCoordinator?.toggleToolbarAction(tool: .magicFrame)
            default:
                if let key = tool.keyEquivalent {
                    try await self.excalidrawWebCoordinator?.toggleToolbarAction(key: key)
                } else {
                    try await self.excalidrawWebCoordinator?.toggleToolbarAction(key: tool.rawValue)
                }
        }
    }
    
    func toggleToolLock(_ locked: Bool) async throws {
        
    }
    
    enum ExtraTool {
        case text2Diagram, mermaid
    }
    
    func toggleExtraTool(_ tool: ExtraTool) async throws {
        switch tool {
            case .text2Diagram:
                try await self.excalidrawWebCoordinator?.toggleToolbarAction(tool: .text2Diagram)
            case .mermaid:
                try await self.excalidrawWebCoordinator?.toggleToolbarAction(tool: .mermaid)
        }
    }
    
    func toggleActionsMenu(isPresented: Bool? = nil) {
        if isPresented == isActionsMenuPresneted { return }
        Task {
            do {
                try await self.excalidrawWebCoordinator?.toggleActionsMenu(isPresented: isPresented ?? !isActionsMenuPresneted)
                await MainActor.run {
                    isActionsMenuPresneted = isPresented ?? !isActionsMenuPresneted
                }
            } catch {
                
            }
        }
    }
    
    func toggleDelegeAction() async throws {
        try await excalidrawWebCoordinator?.toggleDeleteAction()
    }
    
    func togglePencilInterationMode(_ mode: PencilInteractionMode) async throws {
        try await excalidrawWebCoordinator?.togglePencilInterationMode(mode: mode)
    }
    
    func togglePenMode(enabled: Bool, pencilConnected: Bool = false) async throws {
        await MainActor.run {
            self.inPenMode = enabled
        }
        try await excalidrawWebCoordinator?.togglePenMode(enabled: enabled)
        if pencilConnected || !enabled {
            try await excalidrawWebCoordinator?.connectPencil(enabled: enabled)
        }
    }
    
    func toggleToolLock() {
        Task {
            do {
                try await self.excalidrawWebCoordinator?.toggleToolbarAction(key: "q")
            } catch {
                
            }
        }
    }
}

fileprivate struct Cursor: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let width = rect.size.width
        let height = rect.size.height
        path.move(to: CGPoint(x: 0.27273*width, y: 0.27273*height))
        path.addLine(to: CGPoint(x: 0.4615*width, y: 0.80877*height))
        path.addLine(to: CGPoint(x: 0.59091*width, y: 0.59091*height))
        path.addLine(to: CGPoint(x: 0.8085*width, y: 0.50027*height))
        path.addLine(to: CGPoint(x: 0.27273*width, y: 0.27273*height))
        path.closeSubpath()
        path.move(to: CGPoint(x: 0.61364*width, y: 0.61364*height))
        path.addLine(to: CGPoint(x: 0.81818*width, y: 0.81818*height))
        return path
    }
}
