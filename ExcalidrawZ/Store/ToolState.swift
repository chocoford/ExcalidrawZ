//
//  ToolState.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 2024/10/8.
//

import SwiftUI
import WebKit
import Combine
import Logging

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
    case lasso
    
    // extra tool
//    case text2Diagram
//    case mermaid
    
    
    init?(
        from tool: ExcalidrawCanvasView.Coordinator.SetActiveToolMessage.SetActiveToolMessageData.Tool
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
            case .lasso:
                self = .cursor
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
            case .webEmbed, .magicFrame, .lasso:
                nil
        }
    }

    init?(toolbarOrderID: String) {
        switch toolbarOrderID {
            case "eraser":
                self = .eraser
            case "cursor":
                self = .cursor
            case "rectangle":
                self = .rectangle
            case "diamond":
                self = .diamond
            case "ellipse":
                self = .ellipse
            case "arrow":
                self = .arrow
            case "line":
                self = .line
            case "freedraw":
                self = .freedraw
            case "text":
                self = .text
            case "image":
                self = .image
            case "laser":
                self = .laser
            case "frame":
                self = .frame
            case "webEmbed":
                self = .webEmbed
            case "magicFrame":
                self = .magicFrame
            case "hand":
                self = .hand
            case "lasso":
                self = .lasso
            default:
                return nil
        }
    }

    var toolbarOrderID: String {
        switch self {
            case .eraser:
                "eraser"
            case .cursor:
                "cursor"
            case .rectangle:
                "rectangle"
            case .diamond:
                "diamond"
            case .ellipse:
                "ellipse"
            case .arrow:
                "arrow"
            case .line:
                "line"
            case .freedraw:
                "freedraw"
            case .text:
                "text"
            case .image:
                "image"
            case .laser:
                "laser"
            case .frame:
                "frame"
            case .webEmbed:
                "webEmbed"
            case .magicFrame:
                "magicFrame"
            case .hand:
                "hand"
            case .lasso:
                "lasso"
        }
    }

    var supportsOrderedNumericShortcut: Bool {
        switch self {
            case .lasso:
                false
            default:
                true
        }
    }
    
    var localization: String {
        switch self {
            case .hand:
                String(localizable: .toolbarHand)
            case .eraser:
                String(localizable: .toolbarEraser)
            case .cursor:
                String(localizable: .toolbarSelection)
            case .rectangle:
                String(localizable: .toolbarRectangle)
            case .diamond:
                String(localizable: .toolbarDiamond)
            case .ellipse:
                String(localizable: .toolbarEllipse)
            case .arrow:
                String(localizable: .toolbarArrow)
            case .line:
                String(localizable: .toolbarLine)
            case .freedraw:
                String(localizable: .toolbarDraw)
            case .text:
                String(localizable: .toolbarText)
            case .image:
                String(localizable: .toolbarInsertImage)
            case .laser:
                String(localizable: .toolbarLaser)
            case .webEmbed:
                String(localizable: .toolbarWebEmbed)
            case .frame:
                String(localizable: .toolbarFrame)
            case .magicFrame:
                String(localizable: .toolbarMagicFrame)
//            case .lasso:
//                    .localizable(.toolbarLasso)
//            case .text2Diagram:
//                    .localizable(.toolbarText2Diagram)
//            case .mermaid:
//                    .localizable(.toolbarMermaid)
            case .lasso:
                "Lasso Selection"
        }
    }
    
    func help(shortcutLabel: String? = nil) -> String {
        let fixedShortcut = keyEquivalent.flatMap { shortcut -> String? in
            shortcut.isNumber ? nil : String(shortcut).uppercased()
        }
        let shortcuts = [fixedShortcut, shortcutLabel].compactMap { $0 }
        guard !shortcuts.isEmpty else {
            return localization
        }
        let separator = " \(String(localizable: .toolbarOr)) "
        return "\(localization) — \(shortcuts.joined(separator: separator))"
    }

    var help: String {
        help()
    }

    var menuSystemSymbol: SFSymbol {
        switch self {
            case .eraser:
                .pencilSlash
            case .cursor:
                .cursorarrow
            case .rectangle:
                .rectangle
            case .diamond:
                .diamond
            case .ellipse:
                .circle
            case .arrow:
                .lineDiagonalArrow
            case .line:
                .lineDiagonal
            case .freedraw:
                .pencil
            case .text:
                .characterTextbox
            case .image:
                .photoOnRectangle
            case .laser:
                .cursorarrowRays
            case .frame:
                .grid
            case .webEmbed:
                .chevronLeftForwardslashChevronRight
            case .magicFrame:
                .wandAndStarsInverse
            case .hand:
                .handRaised
            case .lasso:
                .selectionPinInOut
        }
    }
    
    @ViewBuilder
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
                Cursor()
                    .stroke(.primary, lineWidth: strokeLineWidth)
                    .aspectRatio(1, contentMode: .fit)

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
            case .lasso:
                Image(systemSymbol: .selectionPinInOut)
                    .resizable()
                    .scaledToFit()
                    .font(.body.weight(.semibold))
//            case .text2Diagram, .mermaid:
//                EmptyView()
        }
    }
}

final class ToolState: ObservableObject {
    let logger = Logger(label: "ToolState")
    var excalidrawWebCoordinator: ExcalidrawCanvasView.Coordinator?

    @Published var activatedTool: ExcalidrawTool? = .cursor
    @Published var isToolLocked: Bool = false
    @Published var previousActivatedTool: ExcalidrawTool? = nil
    var inDragMode: Bool {
        !inPenMode && activatedTool == .hand
    }
    
    @Published var inPenMode: Bool = false
    
    @Published var isActionsMenuPresneted = true
    @Published var isBottomBarPresented = true
    
    enum PencilInteractionMode: Int, Hashable {
        case fingerSelect = 0
        case fingerMove
        case none

        var oneFingerAction: String {
            switch self {
                case .fingerSelect:
                    "select"
                case .fingerMove:
                    "pan"
                case .none:
                    "none"
            }
        }

        var penPriority: Bool {
            switch self {
                case .fingerSelect, .fingerMove:
                    true
                case .none:
                    false
            }
        }
    }

    static let pencilInteractionModeDefaultsKey = "PencilInteractionMode"

    private static func storedPencilInteractionMode() -> PencilInteractionMode {
        let rawValue = UserDefaults.standard.integer(forKey: pencilInteractionModeDefaultsKey)
        return PencilInteractionMode(rawValue: rawValue) ?? .fingerSelect
    }

    var pencilInteractionMode: PencilInteractionMode {
        get { Self.storedPencilInteractionMode() }
        set {
            guard newValue != pencilInteractionMode else { return }
            objectWillChange.send()
            UserDefaults.standard.set(newValue.rawValue, forKey: Self.pencilInteractionModeDefaultsKey)
        }
    }
    
    func setActivedTool(_ tool: ExcalidrawTool?, animation: Animation? = .smooth) {
        withAnimation(animation) {
            self.activatedTool = tool
        }
    }

    func setActiveToolFromWeb(_ tool: ExcalidrawTool, animation: Animation? = .smooth) {
        setActiveToolMirror(tool, animation: animation)
    }

    private func setActiveToolMirror(_ tool: ExcalidrawTool, animation: Animation? = .smooth) {
        guard activatedTool != tool else { return }
        previousActivatedTool = activatedTool
        setActivedTool(tool, animation: animation)
    }
    
    func toggleTool(_ tool: ExcalidrawTool) async throws {
        let coordinator = excalidrawWebCoordinator
        let previousLastTool = coordinator?.lastTool
        if coordinator != nil, previousLastTool == tool {
            return
        }

        coordinator?.lastTool = tool
        logger.debug("Toggle tool: \(String(describing: tool))")

        do {
            switch tool {
                case .webEmbed:
                    try await coordinator?.toggleToolbarAction(tool: .webEmbed)
                case .magicFrame:
                    try await coordinator?.toggleToolbarAction(tool: .magicFrame)
                case .lasso:
                    try await coordinator?.toggleToolbarAction(tool: .lasso)
                default:
                    if let key = tool.keyEquivalent {
                        try await coordinator?.toggleToolbarAction(key: key)
                    } else {
                        try await coordinator?.toggleToolbarAction(key: tool.rawValue)
                    }
            }
            await MainActor.run {
                setActiveToolMirror(tool)
            }
        } catch {
            await MainActor.run {
                if coordinator?.lastTool == tool {
                    coordinator?.lastTool = previousLastTool
                }
            }
            throw error
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
    
    func setPencilInteractionMode(_ mode: PencilInteractionMode) async throws {
        let shouldSync = await MainActor.run {
            self.pencilInteractionMode = mode
            return self.inPenMode
        }
        guard shouldSync else { return }
        try await excalidrawWebCoordinator?.setPointerInputPolicy(mode: mode)
    }
    
    func togglePenMode(enabled: Bool, pencilConnected: Bool = false) async throws {
        let previousPenMode = await MainActor.run { self.inPenMode }
        let interactionMode = await MainActor.run { self.pencilInteractionMode }

        await MainActor.run {
            self.inPenMode = enabled
        }
        do {
            try await excalidrawWebCoordinator?.togglePenMode(enabled: enabled)
            if pencilConnected || !enabled {
                try await excalidrawWebCoordinator?.connectPencil(enabled: enabled)
            }
            if enabled {
                try await excalidrawWebCoordinator?.setPointerInputPolicy(mode: interactionMode)
            }
        } catch {
            await MainActor.run {
                self.inPenMode = previousPenMode
            }
            throw error
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

struct PencilPenModeChangeRequest {
    let enabled: Bool
    let pencilConnected: Bool
}

extension Notification.Name {
    static let pencilInteractionModeDidChange = Notification.Name("PencilInteractionModeDidChange")
    static let pencilPenModeChangeRequested = Notification.Name("PencilPenModeChangeRequested")
    static let pencilPenModeStateRequested = Notification.Name("PencilPenModeStateRequested")
    static let pencilPenModeStateDidChange = Notification.Name("PencilPenModeStateDidChange")
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
