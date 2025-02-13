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
    
    // extra tool
//    case text2Diagram
//    case mermaid
    
    
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
            case .image, .webEmbed, .magicFrame/*, .text2Diagram, .mermaid*/:
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
//            case .text2Diagram:
//                    .localizable(.toolbarText2Diagram)
//            case .mermaid:
//                    .localizable(.toolbarMermaid)
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
//            case .text2Diagram, .mermaid:
//                EmptyView()
        }
    }
}

final class ToolState: ObservableObject {
    var excalidrawWebCoordinator: ExcalidrawView.Coordinator?

    @Published var activatedTool: ExcalidrawTool? = .cursor
    @Published var inDragMode: Bool = false
    
    @Published var inPenMode: Bool = false
    
    @Published var isActionsMenuPresneted = true
    @Published var isBottomBarPresented = true

    
    func toggleTool(_ tool: ExcalidrawTool) async throws {
        switch tool {
            case .webEmbed:
                try await self.excalidrawWebCoordinator?.toggleToolbarAction(tool: .webEmbed)
            case .magicFrame:
                try await self.excalidrawWebCoordinator?.toggleToolbarAction(tool: .magicFrame)
            case .image:
                break
            default:
                if let key = tool.keyEquivalent {
                    try await self.excalidrawWebCoordinator?.toggleToolbarAction(key: key)
                }
        }
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
