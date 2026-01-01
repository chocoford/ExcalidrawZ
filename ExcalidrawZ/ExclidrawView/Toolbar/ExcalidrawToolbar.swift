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
    @Environment(\.containerHorizontalSizeClass) private var containerHorizontalSizeClass
    @Environment(\.alertToast) private var alertToast
    @Environment(\.colorScheme) private var colorScheme
    
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
    @State private var isPDFPickerPresented = false

    
    var body: some View {
        if fileState.currentActiveFile != nil {
            toolbar()
        }
    }
    
    @MainActor @ViewBuilder
    private func toolbar() -> some View {
        toolbarContent()
            .animation(.smooth, value: toolState.activatedTool)
            .animation(.smooth, value: toolState.inDragMode)
            .onChange(of: toolState.activatedTool, debounce: 0.05) { newValue in
                if newValue == nil {
                    toolState.setActivedTool(.cursor)
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
        } else if containerHorizontalSizeClass != .compact, !toolState.inPenMode {
            HStack {
                compactContent()
            }
            .frame(maxWidth: 400)
            .padding(.horizontal, 12)
            .frame(height: 44)
            .background {
                if #available(iOS 26.0, *) {
                    Capsule()
                        .fill(.clear)
                        .glassEffect(.clear, in: Capsule())
                        .shadow(color: .gray.opacity(0.15), radius: colorScheme == .light ? 8 : 0, y: 4)
                } else if #available(macOS 14.0, iOS 17.0, *) {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(.regularMaterial)
                        .stroke(.separator, lineWidth: 0.5)
                } else {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(.regularMaterial)
                }
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
        leadingTollsContent()
        
        ExcalidrawToolbarToolContainer { sizeClass in
            HStack(spacing: 10) {
                ZStack {
                    Color.clear
                    if sizeClass == .dense {
                        denseContent()
                    } else {
                        segmentedPicker(sizeClass: sizeClass)
                    }
                }
            }
        }
        
        if #available(macOS 26.0, iOS 26.0, *),
            !secondaryPickerItems.isEmpty,
           let tool = toolState.activatedTool {
            secondaryPickerItemsMenu(tool: tool)
        }
        
        moreTools()
#endif
    }
    
    @MainActor @ViewBuilder
    private func leadingTollsContent() -> some View {
        Button {
            toolState.toggleToolLock()
        } label: {
            SwiftUI.Group {
                if #available(macOS 14.0, iOS 17.0, *) {
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
    }
    
    @State private var lastActivatedSecondaryTool: ExcalidrawTool?
    
    @MainActor @ViewBuilder
    private func segmentedPicker(
        sizeClass: ExcalidrawToolbarToolSizeClass,
        size: CGFloat = 20,
        withFooter: Bool = true
    ) -> some View {
        HStack(spacing: size / 2) {
            SegmentedPicker(selection: $toolState.activatedTool) {
                primaryToolPikcerItems(size: size, withFooter: withFooter)
            }
            .padding({
                if #available(macOS 26.0, iOS 26.0, *) {
                    .top
                } else {
                    .all
                }
            }(), {
                if #available(macOS 26.0, iOS 26.0, *) {
                    0
                } else {
                    size / 3
                }
            }())
            .background {
                if #available(macOS 26.0, iOS 26.0, *) {
                    
                } else if #available(macOS 14.0, iOS 17.0, *) {
                    RoundedRectangle(cornerRadius: size / 1.6)
                        .fill(.regularMaterial)
                        .stroke(.separator, lineWidth: 0.5)
                } else {
                    RoundedRectangle(cornerRadius: size / 1.6)
                        .fill(.regularMaterial)
                }
            }
            .watchImmediately(of: sizeClass) { newValue in
                if newValue == .compact {
                    primaryPickerItems = [.cursor, .rectangle, .diamond, .ellipse, .arrow, .line]
                    secondaryPickerItems = [.freedraw, .text, .image, .eraser, .laser, .hand, .frame, .webEmbed, .magicFrame]
                } else if newValue == .regular {
                    primaryPickerItems = [.cursor, .rectangle, .diamond, .ellipse, .arrow, .line, .freedraw, .text, .image]
                    secondaryPickerItems = [.eraser, .laser, .hand, .frame, .webEmbed, .magicFrame,]
                } else /*if newValue == .expanded || newValue == .dense*/ {
                    primaryPickerItems = [.cursor, .rectangle, .diamond, .ellipse, .arrow, .line, .freedraw, .text, .image, .eraser, .laser, .hand, .frame, .webEmbed, .magicFrame,]
                    secondaryPickerItems = []
                }
            }
            
            if #available(macOS 26.0, iOS 26.0, *) {
                
            } else if !secondaryPickerItems.isEmpty,
               sizeClass != .expanded,
               let tool = toolState.activatedTool {
                secondaryPickerItemsMenu(tool: tool, size: size)
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
                    }
                    .onChange(of: toolState.activatedTool) { newValue in
                        if let newValue, secondaryPickerItems.contains(newValue) {
                            lastActivatedSecondaryTool = newValue
                        }
                    }
            }
        }
        .padding(.horizontal, {
            if #available(macOS 26.0, iOS 26.0, *) {
                6
            } else {
                0
            }
        }())
    }
    
    @MainActor @ViewBuilder
    private func secondaryPickerItemsMenu(
        tool: ExcalidrawTool,
        size: CGFloat = 20,
    ) -> some View {
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
                toolState.activatedTool != nil && secondaryPickerItems.contains(toolState.activatedTool!)
                ? AnyShapeStyle(Color.accentColor)
                : AnyShapeStyle(HierarchicalShapeStyle.primary)
            )
        } primaryAction: {
            if let lastActivatedSecondaryTool,
               secondaryPickerItems.contains(lastActivatedSecondaryTool) {
                toolState.setActivedTool(lastActivatedSecondaryTool)
            } else {
                toolState.setActivedTool(secondaryPickerItems.first)
            }
        }
        .menuIndicator(.visible)
    }
    
    @State private var primaryPickerItems: [ExcalidrawTool] = []
    @State private var secondaryPickerItems: [ExcalidrawTool] = []
    
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
    private func toolPickerItemView(
        tool: ExcalidrawTool,
        size: CGFloat,
        withFooter: Bool
    ) -> some View {
        SegmentedPickerItem(value: tool) {
            SegmentedToolPickerItemView(
                tool: tool,
                size: size,
                withFooter: withFooter
            )
        }
        .help(tool.help)
    }
    
    @MainActor @ViewBuilder
    private func compactContent() -> some View {
        if toolState.inDragMode {
            HStack(spacing: 20) {
                Color.clear
                    .overlay(alignment: .leading) {
                        if containerHorizontalSizeClass == .compact {
                            if let activeFile = fileState.currentActiveFile {
#if os(iOS)
                                FileICloudSyncStatusIndicator(file: activeFile)
                                    .padding(.horizontal, 8)
#endif
                            } else if case .collaborationFile = fileState.currentActiveFile {
                                CollaborationMembersPopoverButton()
                            }
                        }
                    }
                Color.clear
                    .overlay(alignment: .center) {
#if os(iOS)
                        FileStatusProvider(file: fileState.currentActiveFile) { status in
                            Text(
                                status?.iCloudStatus == .syncing
                                ? .localizable(.iCloudStatusSyncing)
                                : .localizable(.toolbarViewMode)
                            )
                            .animation(.smooth, value: status?.iCloudStatus == .syncing)
                        }
#endif
                    }
                Color.clear
                    .overlay(alignment: .trailing) {
                        Button {
                            if case .file(let file) = fileState.currentActiveFile, file.inTrash {
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
                        .tint(Color.accentColor)
                    }
            }
        } else if let activatedTool = toolState.activatedTool, activatedTool != .cursor {
            if containerHorizontalSizeClass == .compact {
                Text(activatedTool.localization).frame(maxWidth: .infinity, alignment: .leading).padding(.leading, 6)
                Button {
                    if activatedTool == .arrow {
                        Task {
                            try? await toolState.excalidrawWebCoordinator?.toggleToolbarAction(key: "\u{1B}")
                        }
                    }
                    toolState.setActivedTool(.cursor)
                } label: {
                    Label(.localizable(.generalButtonCancel), systemSymbol: .checkmark)
                }
                .modernButtonStyle(style: .glassProminent, shape: .circle)
            } else {
                HStack(spacing: 20) {
                    Text(activatedTool.localization).frame(maxWidth: .infinity, alignment: .leading)
                    Button {
                        if activatedTool == .arrow {
                            Task {
                                try? await toolState.excalidrawWebCoordinator?.toggleToolbarAction(key: "\u{1B}")
                            }
                        }
                        toolState.setActivedTool(.cursor)
                    } label: {
                        Label(.localizable(.generalButtonCancel), systemSymbol: .xmark)
                    }
                }
            }
        } else {
            HStack(spacing: 20) {
                Button {
                    toolState.setActivedTool(.freedraw)
                } label: {
                    Label(.localizable(.toolbarDraw), systemSymbol: .pencilAndOutline)
                }
                Spacer()
                Menu {
                    Button {
                        toolState.setActivedTool(.rectangle)
                    } label: {
                        Label(.localizable(.toolbarRectangle), systemSymbol: .rectangle)
                    }
                    Button {
                        toolState.setActivedTool(.diamond)
                    } label: {
                        Label(.localizable(.toolbarDiamond), systemSymbol: .diamond)
                    }
                    Button {
                        toolState.setActivedTool(.ellipse)
                    } label: {
                        Label(.localizable(.toolbarEllipse), systemSymbol: .circle)
                    }
                    Button {
                        toolState.setActivedTool(.arrow)
                    } label: {
                        Label(.localizable(.toolbarArrow), systemSymbol: .lineDiagonalArrow)
                    }
                    Button {
                        toolState.setActivedTool(.line)
                    } label: {
                        Label(.localizable(.toolbarLine), systemSymbol: .lineDiagonal)
                    }
                    Button {
                        toolState.setActivedTool(.text)
                    } label: {
                        Label(.localizable(.toolbarText), systemSymbol: .characterTextbox)
                    }
                    Button {
                        toolState.setActivedTool(.image)
                    } label: {
                        Label(.localizable(.toolbarInsertImage), systemSymbol: .photoOnRectangle)
                    }

                    Divider()

                    Button {
                        toolState.setActivedTool(.eraser)
                    } label: {
                        if #available(macOS 13.0, *) {
                            Label(.localizable(.toolbarEraser), systemSymbol: .eraser)
                        } else {
                            Label(.localizable(.toolbarEraser), systemSymbol: .pencilSlash)
                        }
                    }
                    Button {
                        toolState.setActivedTool(.laser)
                    } label: {
                        Label(.localizable(.toolbarLaser), systemSymbol: .cursorarrowRays)
                    }
                    Button {
                        toolState.setActivedTool(.frame)
                    } label: {
                        Label(.localizable(.toolbarFrame), systemSymbol: .grid)
                    }
                    Button {
                        toolState.setActivedTool(.webEmbed)
                    } label: {
                        Label(.localizable(.toolbarWebEmbed), systemSymbol: .chevronLeftForwardslashChevronRight)
                    }
                    Button {
                        toolState.setActivedTool(.magicFrame)
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
                        toolState.setActivedTool(.cursor)
                    } label: {
                        Text(.localizable(.generalButtonCancel))
                    }
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
        Text(tool.localization)
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

            Button {
                isPDFPickerPresented.toggle()
            } label: {
                Text(localizable: .toolbarInsertPDF)
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
        .modifier(PDFInsertSheetViewModifier(isPresented: $isPDFPickerPresented))
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
    @EnvironmentObject private var fileState: FileState
    
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
                    // let _ = print(containerSize)
                    Color.clear
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
        let collaborationExtraWidth: CGFloat = 90 // Collaborators
        
        let width: CGFloat = if case .collaborationFile = fileState.currentActiveFile {
            width - collaborationExtraWidth
        } else {
            width
        }
        
        if #available(macOS 13.0, *) {
            if layoutState.isInspectorPresented,
               layoutState.isSidebarPresented {
                switch width {
                    case ..<1510:
                        return .dense
                    case ..<1650:
                        return .compact
                    case ..<1870:
                        return .regular
                    default:
                        return .expanded
                }
            } else if layoutState.isSidebarPresented {
                switch width {
                    case ..<1310:
                        return .dense
                    case ..<1460:
                        return .compact
                    case ..<1660:
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
                    case ..<1760:
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
            case ..<1510:
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
            case .hand:
                tool.icon()
                    .modifier(
                        ExcalidrawToolbarItemModifer(
                            size: size,
                            labelType: .image
                        ) { }
                    )
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
