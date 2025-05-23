//
//  ExcalidrawToolbar.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 2024/8/10.
//

import SwiftUI
import Combine

import SFSafeSymbols
import ChocofordUI

struct ExcalidrawToolbar: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.alertToast) private var alertToast
    
    @EnvironmentObject var fileState: FileState
    @EnvironmentObject var toolState: ToolState
    @EnvironmentObject var layoutState: LayoutState
    
#if canImport(AppKit)
    @State private var window: NSWindow?
#elseif canImport(UIKit)
    @State private var window: UIWindow?
#endif
    @State private var windowFrameCancellable: AnyCancellable?
    @State private var isApplePencilDisconnectConfirmationDialogPresented = false
    
    @State private var isMathInputSheetPresented = false

    
    var body: some View {
        if fileState.currentFile != nil ||
            fileState.currentLocalFile != nil ||
            fileState.currentTemporaryFile != nil {
            toolbar()
        } else if case .room = fileState.currentCollaborationFile {
            toolbar()
        }
    }
    
    @MainActor @ViewBuilder
    private func toolbar() -> some View {
        toolbarContent()
            .onChange(of: toolState.activatedTool, debounce: 0.05) { newValue in
                if newValue == nil {
                    toolState.activatedTool = .cursor
                }
                
                if let tool = newValue {
                    let webCoordinator = toolState.excalidrawWebCoordinator

                    if tool != webCoordinator?.lastTool {
                        Task {
                            do {
                                try await toolState.toggleTool(tool)
                            } catch {
                                alertToast(error)
                            }
                        }
                    }
                }
            }
    }
    
    @MainActor @ViewBuilder
    private func toolbarContent() -> some View {
#if os(iOS)
        if horizontalSizeClass == .compact {
            compactContent()
                .onAppear {
                    // initial drag at ExcalidrawView line 171
                    toolState.inDragMode = true
                }
        } else if horizontalSizeClass == .regular, !toolState.inPenMode {
            HStack {
                compactContent()
            }
            .frame(maxWidth: 400)
            .padding(6)
            .background {
                if #available(macOS 14.0, iOS 17.0, *) {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(.regularMaterial)
                        .stroke(.separator, lineWidth: 0.5)
                } else {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(.regularMaterial)
                }
            }
            .onAppear {
                // initial drag at ExcalidrawView line 171
                toolState.inDragMode = true
            }
        } else if toolState.inPenMode {
            HStack(spacing: 10) {
                Text("Pencil Mode")
            }
            .frame(maxWidth: 400)
            .padding(6)
            .background {
                if #available(macOS 14.0, iOS 17.0, *) {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(.regularMaterial)
                        .stroke(.separator, lineWidth: 0.5)
                } else {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(.regularMaterial)
                }
            }
        }
#elseif os(macOS)
        Button {
            toolState.toggleToolLock()
        } label: {
            SwiftUI.Group {
                if #available(macOS 14.0, *) {
                    Label(.localizable(.toolbarButtonLockToolLabel), systemSymbol: toolState.isToolLocked ? .lock : .lockOpen)
                        .contentTransition(.symbolEffect(.replace))
                } else {
                    Label(.localizable(.toolbarButtonLockToolLabel), systemSymbol: toolState.isToolLocked ? .lock : .lockOpen)
                }
            }
            .foregroundStyle(toolState.isToolLocked ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(HierarchicalShapeStyle.primary))
            .animation(.default, value: toolState.isToolLocked)
        }
        .help("\(String(localizable: .toolbarButtonLockToolHelp)) - Q")
        
        ExcalidrawToolbarToolContainer { sizeClass in
            if sizeClass == .dense {
                denseContent()
            } else {
                content()
            }
        }

        moreTools()
#endif
    }
    
    @State private var lastActivatedSecondaryTool: ExcalidrawTool?
    
    @MainActor @ViewBuilder
    private func content(size: CGFloat = 20, withFooter: Bool = true) -> some View {
        HStack(spacing: size / 2) {
            ExcalidrawToolbarToolContainer { sizeClass in
                SegmentedPicker(selection: $toolState.activatedTool) {
                    primaryToolPikcerItems(size: size, withFooter: withFooter)
                    
                    if sizeClass == .expanded {
                        secondaryToolPikcerItems(size: size, withFooter: withFooter)
                    }
                }
                .padding(size / 3)
                .background {
                    if #available(macOS 14.0, iOS 17.0, *) {
                        RoundedRectangle(cornerRadius: size / 1.6)
                            .fill(.regularMaterial)
                            .stroke(.separator, lineWidth: 0.5)
                    } else {
                        RoundedRectangle(cornerRadius: size / 1.6)
                            .fill(.regularMaterial)
                    }
                }
                .onChange(of: sizeClass) { newValue in
                    if newValue == .compact {
                        primaryPickerItems = [.cursor, .rectangle, .diamond, .ellipse, .arrow, .line]
                        secondaryPickerItems = [.freedraw, .text, .image, .eraser, .laser, .frame, .webEmbed, .magicFrame]
                    } else if newValue == .regular {
                        primaryPickerItems = [.cursor, .rectangle, .diamond, .ellipse, .arrow, .line, .freedraw, .text, .image]
                        secondaryPickerItems = [.eraser, .laser, .frame, .webEmbed, .magicFrame]
                    }
                }
                
                if sizeClass != .expanded,
                   let tool = toolState.activatedTool {
                    Menu {
                        Picker(selection: $toolState.activatedTool) {
                            ForEach(secondaryPickerItems, id: \.self) { tool in
                                densePickerItems(tool: tool)
                                    .tag(tool)
                            }
                        } label: { }
                            .pickerStyle(.inline)
                    } label: {
                        SegmentedToolPickerItemView(
                            tool: {
                                if let lastActivatedSecondaryTool, secondaryPickerItems.contains(lastActivatedSecondaryTool) {
                                    return lastActivatedSecondaryTool
                                } else {
                                    return (secondaryPickerItems.contains(tool) ? tool : secondaryPickerItems.first!)
                                }
                            }(),
                            size: size,
                            withFooter: false
                        )
                        .foregroundStyle(
                            toolState.activatedTool != nil && secondaryPickerItems.contains(toolState.activatedTool!) ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(HierarchicalShapeStyle.primary)
                        )
                    } primaryAction: {
                         if let lastActivatedSecondaryTool,
                            secondaryPickerItems.contains(lastActivatedSecondaryTool) {
                             toolState.activatedTool = lastActivatedSecondaryTool
                        } else {
                            toolState.activatedTool = secondaryPickerItems.first
                        }
                    }
                    .menuIndicator(.visible)
                    .buttonStyle(.borderless)
                    .padding(size / 3)
                    .background {
                        let isSelected = toolState.activatedTool != nil && secondaryPickerItems.contains(toolState.activatedTool!)
                        if #available(macOS 14.0, iOS 17.0, *) {
                            RoundedRectangle(cornerRadius: size / 1.6)
                                .fill(
                                    isSelected ? AnyShapeStyle(Color.accentColor.secondary) : AnyShapeStyle(Material.regularMaterial)
                                )
                                .stroke(.separator, lineWidth: 0.5)
                        } else {
                            RoundedRectangle(cornerRadius: size / 1.6)
                                .fill(
                                    isSelected ? AnyShapeStyle(Color.accentColor.opacity(0.3)) : AnyShapeStyle(Material.regularMaterial)
                                )
                            RoundedRectangle(cornerRadius: size / 1.6)
                                .stroke(.secondary, lineWidth: 0.5)
                        }
//                        if  {
//                            RoundedRectangle(cornerRadius: 6)
//                                .fill(.background)
//                                .shadow(radius: 1, y: 2)
//                                .padding(.trailing, 32)
//                                .padding(.vertical, 6)
//                                .padding(.leading, 6)
//                        }
                    }
                    .onChange(of: toolState.activatedTool) { newValue in
                        if let newValue, secondaryPickerItems.contains(newValue) {
                            lastActivatedSecondaryTool = newValue
                        }
                    }
                }
            }
        }
    }
    
    @State private var primaryPickerItems: [ExcalidrawTool] = [
        .cursor, .rectangle, .diamond, .ellipse, .arrow, .line, .freedraw, .text, .image
    ]
    @State private var secondaryPickerItems: [ExcalidrawTool] = [.eraser, .laser, .frame, .webEmbed, .magicFrame]
    
    @MainActor @ViewBuilder
    private func primaryToolPikcerItems(size: CGFloat, withFooter: Bool) -> some View {
        ForEach(primaryPickerItems, id: \.self) { tool in
            toolPickerItemView(tool: tool, size: size, withFooter: withFooter)
                .tag(tool)
        }
    }
    
    @MainActor @ViewBuilder
    private func secondaryToolPikcerItems(size: CGFloat, withFooter: Bool) -> some View {
        ForEach(secondaryPickerItems, id: \.self) { tool in
            toolPickerItemView(tool: tool, size: size, withFooter: withFooter)
                .tag(tool)
        }
    }
    
    @MainActor @ViewBuilder
    private func toolPickerItemView(tool: ExcalidrawTool, size: CGFloat, withFooter: Bool) -> some View {
        switch tool {
            case .cursor:
                SegmentedPickerItem(value: ExcalidrawTool.cursor) {
                    SegmentedToolPickerItemView(tool: tool, size: size, withFooter: withFooter)
                }
                .help("\(String(localizable: .toolbarSelection)) - V \(String(localizable: .toolbarOr)) 1")
            case .rectangle:
                SegmentedPickerItem(value: ExcalidrawTool.rectangle) {
                    SegmentedToolPickerItemView(tool: tool, size: size, withFooter: withFooter)
                }
                .help("\(String(localizable: .toolbarRectangle)) — R \(String(localizable: .toolbarOr)) 2")
            case .diamond:
                SegmentedPickerItem(value: ExcalidrawTool.diamond) {
                    SegmentedToolPickerItemView(tool: tool, size: size, withFooter: withFooter)
                }
                .help("\(String(localizable: .toolbarDiamond)) — D \(String(localizable: .toolbarOr)) 3")
            case .ellipse:
                SegmentedPickerItem(value: ExcalidrawTool.ellipse) {
                    SegmentedToolPickerItemView(tool: tool, size: size, withFooter: withFooter)
                }
                .help("\(String(localizable: .toolbarEllipse)) — O \(String(localizable: .toolbarOr)) 4")
            case .arrow:
                SegmentedPickerItem(value: ExcalidrawTool.arrow) {
                    SegmentedToolPickerItemView(tool: tool, size: size, withFooter: withFooter)
                }
                .help("\(String(localizable: .toolbarArrow)) — A \(String(localizable: .toolbarOr)) 5")
            case .line:
                SegmentedPickerItem(value: ExcalidrawTool.line) {
                    SegmentedToolPickerItemView(tool: tool, size: size, withFooter: withFooter)
                }
                .help("\(String(localizable: .toolbarLine)) — L \(String(localizable: .toolbarOr)) 6")
            case .freedraw:
                SegmentedPickerItem(value: ExcalidrawTool.freedraw) {
                    SegmentedToolPickerItemView(tool: tool, size: size, withFooter: withFooter)
                }
                .help("\(String(localizable: .toolbarDraw)) — P \(String(localizable: .toolbarOr)) 7")
            case .text:
                SegmentedPickerItem(value: ExcalidrawTool.text) {
                    SegmentedToolPickerItemView(tool: tool, size: size, withFooter: withFooter)
                }
                .help("\(String(localizable: .toolbarText)) — T \(String(localizable: .toolbarOr)) 8")
            case .image:
                SegmentedPickerItem(value: ExcalidrawTool.image) {
                    SegmentedToolPickerItemView(tool: tool, size: size, withFooter: withFooter)
                }
                .help("\(String(localizable: .toolbarInsertImage)) — 9")
            case .eraser:
                SegmentedPickerItem(value: ExcalidrawTool.eraser) {
                    SegmentedToolPickerItemView(tool: tool, size: size, withFooter: withFooter)
                }
                .help("\(String(localizable: .toolbarEraser)) — E \(String(localizable: .toolbarOr)) 0")
            case .laser:
                SegmentedPickerItem(value: ExcalidrawTool.laser) {
                    SegmentedToolPickerItemView(tool: tool, size: size, withFooter: withFooter)
                }
                .help("\(String(localizable: .toolbarLaser)) — K")
            case .frame:
                SegmentedPickerItem(value: ExcalidrawTool.frame) {
                    SegmentedToolPickerItemView(tool: tool, size: size, withFooter: withFooter)
                }
                .help("\(String(localizable: .toolbarFrame)) - F")
            case .webEmbed:
                SegmentedPickerItem(value: ExcalidrawTool.webEmbed) {
                    SegmentedToolPickerItemView(tool: tool, size: size, withFooter: withFooter)
                }
                .help("\(String(localizable: .toolbarWebEmbed))")
            case .magicFrame:
                SegmentedPickerItem(value: ExcalidrawTool.magicFrame) {
                    SegmentedToolPickerItemView(tool: tool, size: size, withFooter: withFooter)
                }
                .help("\(String(localizable: .toolbarMagicFrame))")
        }
    }
    
    @MainActor @ViewBuilder
    private func compactContent() -> some View {
        if toolState.inDragMode {
            Button { /* Do Nothing */ } label: {
                Text(.localizable(.toolbarEdit))
            }
            .opacity(0)
            Spacer()
            Text(.localizable(.toolbarViewMode))
            Spacer()
            Button {
                if fileState.currentFile?.inTrash == true {
                    layoutState.isResotreAlertIsPresented.toggle()
                } else {
                    Task {
                        do {
                            try await toolState.excalidrawWebCoordinator?.toggleToolbarAction(key: "h")
                        } catch {
                            alertToast(error)
                        }
                    }
                }
            } label: {
                Text(.localizable(.toolbarEdit))
            }
        } else if let activatedTool = toolState.activatedTool, activatedTool != .cursor {
            Text(activatedTool.localization)
            Spacer()
            Button {
                if activatedTool == .arrow {
                    Task {
                        try? await toolState.excalidrawWebCoordinator?.toggleToolbarAction(key: "\u{1B}")
                    }
                }
                toolState.activatedTool = .cursor
            } label: {
                Label(.localizable(.generalButtonCancel), systemSymbol: .xmark)
            }
        } else {
            Button {
                toolState.activatedTool = .freedraw
            } label: {
                Label(.localizable(.toolbarDraw), systemSymbol: .pencilAndOutline)
            }
            Spacer()
            Menu {
                Button {
                    toolState.activatedTool = .rectangle
                } label: {
                    Label(.localizable(.toolbarRectangle), systemSymbol: .rectangle)
                }
                Button {
                    toolState.activatedTool = .diamond
                } label: {
                    Label(.localizable(.toolbarDiamond), systemSymbol: .diamond)
                }
                Button {
                    toolState.activatedTool = .ellipse
                } label: {
                    Label(.localizable(.toolbarEllipse), systemSymbol: .circle)
                }
                Button {
                    toolState.activatedTool = .arrow
                } label: {
                    Label(.localizable(.toolbarArrow), systemSymbol: .lineDiagonalArrow)
                }
                Button {
                    toolState.activatedTool = .line
                } label: {
                    Label(.localizable(.toolbarLine), systemSymbol: .lineDiagonal)
                }
                Button {
                    toolState.activatedTool = .text
                } label: {
                    Label(.localizable(.toolbarText), systemSymbol: .characterTextbox)
                }
                Button {
                    toolState.activatedTool = .image
                } label: {
                    Label(.localizable(.toolbarInsertImage), systemSymbol: .photoOnRectangle)
                }
                
                Divider()
                
                Button {
                    toolState.activatedTool = .eraser
                } label: {
                    if #available(macOS 13.0, *) {
                        Label(.localizable(.toolbarEraser), systemSymbol: .eraser)
                    } else {
                        Label(.localizable(.toolbarEraser), systemSymbol: .pencilSlash)
                    }
                }
                Button {
                    toolState.activatedTool = .laser
                } label: {
                    Label(.localizable(.toolbarLaser), systemSymbol: .cursorarrowRays)
                }
                Button {
                    toolState.activatedTool = .frame
                } label: {
                    Label(.localizable(.toolbarFrame), systemSymbol: .grid)
                }
                Button {
                    toolState.activatedTool = .webEmbed
                } label: {
                    Label(.localizable(.toolbarWebEmbed), systemSymbol: .chevronLeftForwardslashChevronRight)
                }
                Button {
                    toolState.activatedTool = .magicFrame
                } label: {
                    Label(.localizable(.toolbarMagicFrame), systemSymbol: .wandAndStarsInverse)
                }
            } label: {
                if toolState.activatedTool == .cursor {
                    Label(.localizable(.toolbarShapesAndTools), systemSymbol: .squareOnCircle)
                } else {
                    activeShape()
                        .foregroundStyle(Color.accentColor)
                }
            }
#if os(iOS)
            .menuOrder(.fixed)
#endif
            
            Spacer()
            
            moreTools()
            
            Spacer()
            
            if toolState.activatedTool == .cursor {
                Button {
                    Task {
                        try? await toolState.excalidrawWebCoordinator?.toggleToolbarAction(key: "h")
                    }
                } label: {
                    Text(.localizable(.generalButtonDone))
                }
            } else {
                Button {
                    toolState.activatedTool = .cursor
                } label: {
                    Text(.localizable(.generalButtonCancel))
                }
            }

        }
    }
    
    @MainActor @ViewBuilder
    private func denseContent() -> some View {
        HStack {
            Picker(selection: $toolState.activatedTool) {
                ForEach(ExcalidrawTool.allCases, id: \.self) { tool in
                    densePickerItems(tool: tool)
                        .tag(tool)
                }
            } label: {
                Text(.localizable(.toolbarActiveToolTitle))
            }
            .pickerStyle(.menu)
            .fixedSize()
        }
    }
    
    @MainActor @ViewBuilder
    private func densePickerItems(tool: ExcalidrawTool) -> some View {
        switch tool {
            case .cursor:
                Text(.localizable(.toolbarSelection))
            case .rectangle:
                Text(.localizable(.toolbarRectangle))
            case .diamond:
                Text(.localizable(.toolbarDiamond))
            case .ellipse:
                Text(.localizable(.toolbarEllipse))
            case .arrow:
                Text(.localizable(.toolbarArrow))
            case .line:
                Text(.localizable(.toolbarLine))
            case .freedraw:
                Text(.localizable(.toolbarDraw))
            case .text:
                Text(.localizable(.toolbarText))
            case .image:
                Text(.localizable(.toolbarInsertImage))
            case .eraser:
                Text(.localizable(.toolbarEraser))
            case .laser:
                Text(.localizable(.toolbarLaser))
            case .frame:
                Text(.localizable(.toolbarFrame))
            case .webEmbed:
                Text(.localizable(.toolbarWebEmbed))
            case .magicFrame:
                Text(.localizable(.toolbarMagicFrame))
        }
    }

    @MainActor @ViewBuilder
    private func activeShape() -> some View {
        switch toolState.activatedTool {
            case .rectangle:
                Label(.localizable(.toolbarRectangle), systemSymbol: .rectangle)
            case .diamond:
                Label(.localizable(.toolbarDiamond), systemSymbol: .diamond)
            case .ellipse:
                Label(.localizable(.toolbarEllipse), systemSymbol: .ellipsis)
            case .arrow:
                Label(.localizable(.toolbarArrow), systemSymbol: .lineDiagonalArrow)
            case .line:
                Label(.localizable(.toolbarLine), systemSymbol: .lineDiagonal)
            default:
                Label(.localizable(.toolbarShapes), systemSymbol: .squareOnCircle)
        }
    }
    
    
    @MainActor @ViewBuilder
    private func moreTools() -> some View {
        Menu {
#if DEBUG
            Button {
                Task {
                    try? await toolState.excalidrawWebCoordinator?.toggleToolbarAction(tool: .text2Diagram)
                }
            } label: {
                Text(.localizable(.toolbarText2Diagram))
            }
#endif
            Button {
                Task {
                    try? await toolState.excalidrawWebCoordinator?.toggleToolbarAction(tool: .mermaid)
                }
            } label: {
                Text(.localizable(.toolbarMermaid))
            }
            
            Button {
                isMathInputSheetPresented.toggle()
            } label: {
                Text(.localizable(.toolbarLatexMath))
            }
        } label: {
            if #available(macOS 15.0, iOS 18.0, *) {
                Label(.localizable(.toolbarMoreTools), systemImage: "xmark.triangle.circle.square")
            } else if #available(macOS 13.0, iOS 16.0, *) {
                Label(.localizable(.toolbarMoreTools), systemSymbol: .chartXyaxisLine)
            } else {
                Label(.localizable(.toolbarMoreTools), systemSymbol: .chartXyaxisLine)
            }
        }
        .menuIndicator(.hidden)
#if os(iOS)
        .menuOrder(.fixed)
#endif
        .modifier(MathInputSheetViewModifier(isPresented: $isMathInputSheetPresented))
    }
}

enum ExcalidrawToolbarToolSizeClass {
    case dense
    case compact
    case regular
    case expanded
}

struct ExcalidrawToolbarToolContainer<Content: View>: View {
    @EnvironmentObject private var layoutState: LayoutState
    
    var content: (_ size: ExcalidrawToolbarToolSizeClass) -> Content
    
    init(
        @ViewBuilder content: @escaping (_ size: ExcalidrawToolbarToolSizeClass) -> Content
    ) {
        self.content = content
    }
    
    @State private var sizeClass: ExcalidrawToolbarToolSizeClass = .dense
    
    var body: some View {
        content(sizeClass)
            .background {
                WithContainerSize { containerSize in
                    let _ = print(containerSize)
                    Color.clear
                    // , throttle: 0.3, latest: true
                        .watchImmediately(of: containerSize) { newValue in
                            let newSizeClass = getSizeClass(containerSize.width)
                            if newSizeClass != sizeClass {
                                self.sizeClass = newSizeClass
                            }
                        }
                        .onChange(of: layoutState.isInspectorPresented) { _ in
                            DispatchQueue.main.async {
                                self.sizeClass = getSizeClass(containerSize.width)
                            }
                        }
                        .onChange(of: layoutState.isSidebarPresented) { _ in
                            DispatchQueue.main.async {
                                self.sizeClass = getSizeClass(containerSize.width)
                            }
                        }
                }
            }
    }
    
    private func getSizeClass(_ width: CGFloat) -> ExcalidrawToolbarToolSizeClass {
        if #available(macOS 13.0, *) {
            if layoutState.isInspectorPresented,
               layoutState.isSidebarPresented {
                switch width {
                    case ..<1510:
                        return .dense
                    case ..<1650:
                        return .compact
                    default:
                        return .regular
                }
            } else if layoutState.isSidebarPresented {
                switch width {
                    case ..<1295:
                        return .dense
                    case ..<1450:
                        return .compact
                    case ..<1610:
                        return .regular
                    default:
                        return .expanded
                }
            } else if layoutState.isInspectorPresented {
                switch width {
                    case ..<1410:
                        return .dense
                    case ..<1570:
                        return .compact
                    case ..<1710:
                        return .regular
                    default:
                        return .expanded
                }
            }
        }
        switch width {
            case ..<1170:
                return .dense
            case ..<1330:
                return .compact
            case ..<1460:
                return .regular
            default:
                return .expanded
        }
    }
}

struct SegmentedToolPickerItemView: View {
    var tool: ExcalidrawTool
    var size: CGFloat
    var withFooter: Bool
    
    init(tool: ExcalidrawTool, size: CGFloat, withFooter: Bool) {
        self.tool = tool
        self.size = size
        self.withFooter = withFooter
    }
    
    var body: some View {
        switch tool {
            case .cursor:
                Cursor()
                    .stroke(.primary, lineWidth: 1.5)
                    .aspectRatio(1, contentMode: .fit)
                    .modifier(
                        ExcalidrawToolbarItemModifer(size: size, labelType: .svg) {
                            if withFooter {
                                Text("1")
                            }
                        }
                    )
            case .rectangle:
                RoundedRectangle(cornerRadius: 3)
                    .stroke(.primary, lineWidth: 1.5)
                    .modifier(
                        ExcalidrawToolbarItemModifer(size: size, labelType: .nativeShape) {
                            if withFooter {
                                Text("2")
                            }
                        }
                    )
                
            case .diamond:
                RoundedRectangle(cornerRadius: 3)
                    .stroke(.primary, lineWidth: 1.5)
                    .rotationEffect(.degrees(45))
                    .modifier(
                        ExcalidrawToolbarItemModifer(size: size, labelType: .nativeShape) {
                            if withFooter {
                                Text("3")
                            }
                        }
                    )
            case .ellipse:
                Circle()
                    .stroke(.primary, lineWidth: 1.5)
                    .modifier(
                        ExcalidrawToolbarItemModifer(size: size, labelType: .nativeShape) {
                            if withFooter {
                                Text("4")
                            }
                        }
                    )
            case .arrow:
                Image(systemSymbol: .arrowRight)
                    .resizable()
                    .scaledToFit()
                    .font(.body.weight(.semibold))
                    .modifier(
                        ExcalidrawToolbarItemModifer(size: size, labelType: .image) {
                            if withFooter {
                                Text("5")
                            }
                        }
                    )
            case .line:
                Capsule()
                    .stroke(.primary, lineWidth: 1.5)
                    .frame(height: 1)
                    .modifier(
                        ExcalidrawToolbarItemModifer(size: size, labelType: .nativeShape) {
                            if withFooter {
                                Text("6")
                            }
                        }
                    )
            case .freedraw:
                Image(systemSymbol: .pencil)
                    .resizable()
                    .scaledToFit()
                    .font(.body.weight(.semibold))
                    .modifier(
                        ExcalidrawToolbarItemModifer(size: size, labelType: .image) {
                            if withFooter {
                                Text("7")
                            }
                        }
                    )
            case .text:
                Image(systemSymbol: .character)
                    .resizable()
                    .scaledToFit()
                    .font(.body.weight(.semibold))
                    .modifier(
                        ExcalidrawToolbarItemModifer(size: size, labelType: .image) {
                            if withFooter {
                                Text("8")
                            }
                        }
                    )
            case .image:
                Image(systemSymbol: .photo)
                    .resizable()
                    .scaledToFit()
                    .font(.body.weight(.semibold))
                    .modifier(
                        ExcalidrawToolbarItemModifer(size: size, labelType: .image) {
                            if withFooter {
                                Text("9")
                            }
                        }
                    )
            case .eraser:
                if #available(macOS 13.0, *) {
                    Image(systemSymbol: .eraserLineDashed)
                        .resizable()
                        .scaledToFit()
                        .font(.body.weight(.semibold))
                        .modifier(
                            ExcalidrawToolbarItemModifer(size: size, labelType: .image) {
                                if withFooter {
                                    Text("0")
                                }
                            }
                        )
                } else {
                    Image(systemSymbol: .pencilSlash)
                        .resizable()
                        .scaledToFit()
                        .font(.body.weight(.semibold))
                        .modifier(
                            ExcalidrawToolbarItemModifer(size: size, labelType: .image) {
                                if withFooter {
                                    Text("0")
                                }
                            }
                        )
                }
            case .laser:
                Image(systemSymbol: .cursorarrowRays)
                    .resizable()
                    .scaledToFit()
                    .font(.body.weight(.semibold))
                    .modifier(
                        ExcalidrawToolbarItemModifer(size: size, labelType: .image) {
                            if withFooter {
                                Text("K")
                            }
                        }
                    )
            case .frame:
                Image(systemSymbol: .grid)
                    .resizable()
                    .scaledToFit()
                    .font(.body.weight(.semibold))
                    .modifier(
                        ExcalidrawToolbarItemModifer(size: size, labelType: .image) {
                            if withFooter {
                                Text("F")
                            }
                        }
                    )
            case .webEmbed:
                Image(systemSymbol: .chevronLeftForwardslashChevronRight)
                    .resizable()
                    .scaledToFit()
                    .font(.body.weight(.semibold))
                    .modifier(
                        ExcalidrawToolbarItemModifer(size: size, labelType: .image) {}
                    )
                
            case .magicFrame:
                Image(systemSymbol: .wandAndStarsInverse)
                    .resizable()
                    .scaledToFit()
                    .font(.body.weight(.semibold))
                    .modifier(
                        ExcalidrawToolbarItemModifer(size: size, labelType: .image) {}
                    )
        }
    }
}

struct ExcalidrawToolbarItemModifer: ViewModifier {
    enum LabelType {
        case nativeShape
        case svg
        case image
    }
    
    var labelType: LabelType
    var footer: AnyView
    
    init<Footer : View>(
        size: CGFloat = 20,
        labelType: LabelType,
        @ViewBuilder footer: () -> Footer
    ) {
        self.size = size
        self.labelType = labelType
        self.footer = AnyView(footer())
    }
    
    var size: CGFloat
    
    func body(content: Content) -> some View {
        content
            .padding(labelType == .nativeShape ? size / 6 : labelType == .svg ? 0 : size / 6)
            .aspectRatio(1, contentMode: .fit)
            .frame(width: size, height: size)
            .padding(size / 5)
            .overlay(alignment: .bottomTrailing) {
                footer
                    .font(.footnote)
            }
            .padding(1)
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

#Preview {
    ExcalidrawToolbar()
        .background(.background)
}
