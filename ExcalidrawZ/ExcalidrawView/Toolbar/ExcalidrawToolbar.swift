//
//  ExcalidrawToolbar.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 2024/8/10.
//

import SwiftUI

import SFSafeSymbols
import ChocofordUI

#if canImport(UIKit)
import UIKit
#endif

struct ExcalidrawToolbar: View {
    @Environment(\.containerHorizontalSizeClass) private var containerHorizontalSizeClass
    @Environment(\.alertToast) private var alertToast
    
    @EnvironmentObject var appPreference: AppPreference
    @EnvironmentObject var fileState: FileState
    @EnvironmentObject var toolState: ToolState
    @EnvironmentObject var layoutState: LayoutState

    var body: some View {
        if fileState.currentActiveFile != nil {
            toolbar()
        }
    }
    
    @ViewBuilder
    private func toolbar() -> some View {
        toolbarContent()
            .animation(.smooth, value: toolState.activatedTool)
            .animation(.smooth, value: toolState.inDragMode)
            .watch(value: toolState.activatedTool) { newValue in
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
    
    @ViewBuilder
    private func toolbarContent() -> some View {
        if containerHorizontalSizeClass == .compact {
            compactContent()
        } else {
#if os(iOS)
            HStack(spacing: 10) {
                adaptiveToolPickerContent()
            }
#else
            adaptiveToolPickerContent()
#endif
        }
    }
    
    @ViewBuilder
    private func adaptiveToolPickerContent() -> some View {
        let toolOrder = appPreference.toolbarToolOrder

        leadingTollsContent()
#if os(iOS)
            .excalidrawToolbarSurface(.circle)
#endif
        ExcalidrawToolbarToolContainer { sizeClass in
            let pickerItems = toolOrder.pickerItems(for: sizeClass)
            
            HStack(spacing: 10) {
                ZStack {
                    Color.clear
                    if sizeClass == .dense {
                        denseContent(toolOrder.tools)
                    } else {
                        segmentedPicker(
                            sizeClass: sizeClass,
                            primaryPickerItems: pickerItems.primary,
                            secondaryPickerItems: pickerItems.secondary,
                            toolOrder: toolOrder
                        )
                    }
                }
            }
#if os(iOS)
            .excalidrawToolbarSurface(.capsule)
#endif
            
            if #available(macOS 26.0, iOS 26.0, *),
               !pickerItems.secondary.isEmpty,
               sizeClass != .dense,
               let tool = toolState.activatedTool {
                secondaryPickerItemsMenu(
                    tool: tool,
                    secondaryPickerItems: pickerItems.secondary
                )
#if os(iOS)
                .excalidrawToolbarSurface(.circle)
#endif
            }
        }
        
        moreTools()
#if os(iOS)
            .excalidrawToolbarSurface(.circle)
#endif
        
    }
    
    @ViewBuilder
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
    
    @ViewBuilder
    private func segmentedPicker(
        sizeClass: ExcalidrawToolbarToolSizeClass,
        primaryPickerItems: [ExcalidrawTool],
        secondaryPickerItems: [ExcalidrawTool],
        toolOrder: ExcalidrawToolbarToolOrder,
        size: CGFloat = 20,
        withFooter: Bool = true
    ) -> some View {
        HStack(spacing: size / 2) {
            SegmentedPicker(selection: $toolState.activatedTool) {
                primaryToolPikcerItems(
                    primaryPickerItems,
                    size: size,
                    withFooter: withFooter,
                    toolOrder: toolOrder
                )
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
            if #available(macOS 26.0, iOS 26.0, *) {
                
            } else if !secondaryPickerItems.isEmpty,
                      sizeClass != .expanded,
                      let tool = toolState.activatedTool {
                secondaryPickerItemsMenu(
                    tool: tool,
                    secondaryPickerItems: secondaryPickerItems,
                    size: size
                )
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
                .watch(value: toolState.activatedTool) { newValue in
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
    
    @ViewBuilder
    private func secondaryPickerItemsMenu(
        tool: ExcalidrawTool,
        secondaryPickerItems: [ExcalidrawTool],
        size: CGFloat = 20,
    ) -> some View {
#if os(iOS)
        Menu {
            secondaryPickerItemsPicker(secondaryPickerItems)
        } label: {
            secondaryPickerItemsMenuLabel(
                secondaryPickerItems: secondaryPickerItems,
                size: size
            )
            .foregroundStyle(
                toolState.activatedTool != nil && secondaryPickerItems.contains(toolState.activatedTool!)
                ? AnyShapeStyle(Color.accentColor)
                : AnyShapeStyle(HierarchicalShapeStyle.primary)
            )
            .contentShape(Rectangle())
        }
        .menuIndicator(.hidden)
#else
        Menu {
            secondaryPickerItemsPicker(secondaryPickerItems)
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
#endif
    }
    
    @ViewBuilder
    private func secondaryPickerItemsPicker(_ secondaryPickerItems: [ExcalidrawTool]) -> some View {
        Picker(selection: $toolState.activatedTool) {
            ForEach(secondaryPickerItems, id: \.self) { tool in
                densePickerItems(tool: tool)
                    .tag(tool)
            }
        } label: { }
            .pickerStyle(.inline)
    }
    
    @ViewBuilder
    private func denseContent(_ toolbarTools: [ExcalidrawTool]) -> some View {
        HStack {
            Picker(selection: $toolState.activatedTool) {
                ForEach(toolbarTools, id: \.self) { tool in
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

    @ViewBuilder
    private func secondaryPickerItemsMenuLabel(
        secondaryPickerItems: [ExcalidrawTool],
        size: CGFloat
    ) -> some View {
        if let tool = toolState.activatedTool,
           secondaryPickerItems.contains(tool) {
            SegmentedToolPickerItemView(
                tool: tool,
                size: size,
                withFooter: false
            )
        } else {
            Image(systemSymbol: .line3Horizontal)
                .modifier(
                    ExcalidrawToolbarItemModifer(size: size, labelType: .image) {
                        EmptyView()
                    }
                )
        }
    }
    
    @ViewBuilder
    private func primaryToolPikcerItems(
        _ primaryPickerItems: [ExcalidrawTool],
        size: CGFloat,
        withFooter: Bool,
        toolOrder: ExcalidrawToolbarToolOrder
    ) -> some View {
        ForEach(primaryPickerItems, id: \.self) { tool in
            let shortcutLabel = toolOrder.shortcutLabel(for: tool)
            toolPickerItemView(
                tool: tool,
                size: size,
                withFooter: withFooter,
                shortcutLabel: shortcutLabel
            )
                .tag(tool)
        }
    }
    
    @ViewBuilder
    private func toolPickerItemView(
        tool: ExcalidrawTool,
        size: CGFloat,
        withFooter: Bool,
        shortcutLabel: String?
    ) -> some View {
        SegmentedPickerItem(value: tool) {
            SegmentedToolPickerItemView(
                tool: tool,
                size: size,
                withFooter: withFooter,
                shortcutLabel: shortcutLabel
            )
        }
        .help(tool.help(shortcutLabel: shortcutLabel))
    }
    
    @ViewBuilder
    private func compactContent() -> some View {
        if toolState.inDragMode {
            compactDragModeControls
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
            let toolOrder = appPreference.toolbarToolOrder

            HStack(spacing: 20) {
                Button {
                    toolState.setActivedTool(.freedraw)
                } label: {
                    Label(.localizable(.toolbarDraw), systemSymbol: .pencilAndOutline)
                }
                Spacer()
                Menu {
                    compactShapeAndToolMenuItems(toolOrder: toolOrder)
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
                    if let coordinator = toolState.excalidrawWebCoordinator {
                        CursorModeTrailingButton(coordinator: coordinator) {
                            toolState.setActivedTool(.hand)
                        }
                    } else {
                        Button {
                            toolState.setActivedTool(.hand)
                        } label: {
                            Text(.localizable(.generalButtonDone))
                        }
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
    
    @ViewBuilder
    private var compactDragModeControls: some View {
        compactStatusBar
        
        Spacer(minLength: 0)
        
        compactInspectorTabButton(
            tab: .preference,
            icon: .sliderHorizontal3,
            title: String(localizable: .canvasPreferencesTitle)
        )
        if shouldCollapseCompactInspectorTabs {
            compactInspectorTabButton(
                tab: .aiChat,
                icon: .sparkles,
                title: "AI Chat",
                action: toggleCompactAIChatPresentation
            )
            compactInspectorTabsMenu()
        } else {
            compactInspectorTabButton(
                tab: .search,
                icon: .magnifyingglass,
                title: String(localizable: .searchButtonTitle)
            )
            .keyboardShortcut("f", modifiers: .command)
            compactInspectorTabButton(
                tab: .library,
                icon: .book,
                title: String(localizable: .librariesTitle)
            )
            compactInspectorTabButton(
                tab: .history,
                icon: .clockArrowCirclepath,
                title: String(localizable: .checkpoints)
            )
            compactInspectorTabButton(
                tab: .presentation,
                icon: .play,
                title: String(localizable: .presentationTitle)
            )
            compactInspectorTabButton(
                tab: .aiChat,
                icon: .sparkles,
                title: "AI Chat",
                action: toggleCompactAIChatPresentation
            )
        }
        compactEditButton
    }
    
    @ViewBuilder
    private var compactStatusBar: some View {
#if os(iOS)
        if let activeFile = fileState.currentActiveFile {
            FileICloudSyncStatusIndicator(file: activeFile)
                .frame(width: 28, height: 28)
        }
#endif
    }
    
    private var shouldCollapseCompactInspectorTabs: Bool {
#if os(iOS)
        guard containerHorizontalSizeClass == .compact else { return false }
        return UIScreen.main.bounds.width < 390
#else
        return false
#endif
    }
    
    @ViewBuilder
    private var compactEditButton: some View {
        Button {
            if case .file(let file) = fileState.currentActiveFile, file.inTrash {
                layoutState.isResotreAlertIsPresented.toggle()
            } else {
                toolState.setActivedTool(.cursor)
            }
        } label: {
            Label(.localizable(.toolbarEdit), systemSymbol: .pencil)
                .labelStyle(.iconOnly)
                .frame(width: 28, height: 28)
        }
        .modernButtonStyle(style: .glassProminent, size: .small, shape: .circle)
        .help(String(localizable: .toolbarEdit))
    }
    
    @ViewBuilder
    private func compactInspectorTabButton(
        tab: LayoutState.InspectorTab,
        icon: SFSymbol,
        title: String,
        action: (() -> Void)? = nil
    ) -> some View {
        let isDisabled = compactInspectorTabIsDisabled(tab)
        let isActive = compactInspectorTabIsActive(tab)
        
        Button {
            guard !isDisabled else { return }
            if let action {
                action()
            } else {
                layoutState.toggleInspector(tab)
            }
        } label: {
            Label(title, systemSymbol: icon)
                .labelStyle(.iconOnly)
                .font(.system(size: 16))
                .foregroundStyle(isActive ? Color.accentColor : Color.primary)
                .frame(width: 28, height: 28)
        }
        .help(title)
        .opacity(isDisabled && !isActive ? 0.55 : 1)
        .allowsHitTesting(!isDisabled)
    }
    
    @ViewBuilder
    private func compactInspectorTabsMenu() -> some View {
        Menu {
            compactInspectorTabMenuButton(
                tab: .search,
                icon: .magnifyingglass,
                title: String(localizable: .searchButtonTitle)
            )
            .keyboardShortcut("f", modifiers: .command)
            compactInspectorTabMenuButton(
                tab: .history,
                icon: .clockArrowCirclepath,
                title: String(localizable: .checkpoints)
            )
            compactInspectorTabMenuButton(
                tab: .library,
                icon: .book,
                title: String(localizable: .librariesTitle)
            )
            compactInspectorTabMenuButton(
                tab: .presentation,
                icon: .play,
                title: String(localizable: .presentationTitle)
            )
        } label: {
            Label(.localizable(.generalButtonMore), systemSymbol: .ellipsis)
                .labelStyle(.iconOnly)
                .font(.system(size: 16))
                .foregroundStyle(compactCollapsedInspectorTabsContainActive ? Color.accentColor : Color.primary)
                .frame(width: 28, height: 28)
        }
        .menuIndicator(.hidden)
        .help(String(localizable: .generalButtonMore))
#if os(iOS)
        .menuOrder(.fixed)
#endif
    }
    
    @ViewBuilder
    private func compactInspectorTabMenuButton(
        tab: LayoutState.InspectorTab,
        icon: SFSymbol,
        title: String
    ) -> some View {
        let isDisabled = compactInspectorTabIsDisabled(tab)
        Button {
            guard !isDisabled else { return }
            layoutState.toggleInspector(tab)
        } label: {
            Label(title, systemSymbol: icon)
        }
        .disabled(isDisabled)
    }
    
    private var compactCollapsedInspectorTabsContainActive: Bool {
        [LayoutState.InspectorTab.search, .history, .library, .presentation].contains { tab in
            compactInspectorTabIsActive(tab)
        }
    }
    
    private func compactInspectorTabIsDisabled(_ tab: LayoutState.InspectorTab) -> Bool {
        switch tab {
            case .history:
                return fileState.currentActiveFile == nil
            default:
                return false
        }
    }
    
    private func compactInspectorTabIsActive(_ tab: LayoutState.InspectorTab) -> Bool {
        if tab == .aiChat, layoutState.isAIChatIslandMode {
            return true
        }
        return layoutState.isInspectorPresented && layoutState.activeInspectorTab == tab
    }
    
    private func toggleCompactAIChatPresentation() {
        if layoutState.isAIChatIslandMode {
            layoutState.isAIChatIslandMode = false
        } else {
            layoutState.toggleInspector(.aiChat)
        }
    }
    
    @ViewBuilder
    private func densePickerItems(tool: ExcalidrawTool) -> some View {
        Text(tool.localization)
    }

    private func compactShapeAndToolMenuTools(
        toolOrder: ExcalidrawToolbarToolOrder
    ) -> [ExcalidrawTool] {
        toolOrder.tools.filter { tool in
            switch tool {
                case .cursor, .freedraw, .hand, .lasso:
                    false
                default:
                    true
            }
        }
    }

    @ViewBuilder
    private func compactShapeAndToolMenuItems(
        toolOrder: ExcalidrawToolbarToolOrder
    ) -> some View {
        ForEach(compactShapeAndToolMenuTools(toolOrder: toolOrder), id: \.self) { tool in
            compactShapeAndToolMenuButton(tool)
        }
    }

    @ViewBuilder
    private func compactShapeAndToolMenuButton(_ tool: ExcalidrawTool) -> some View {
        Button {
            toolState.setActivedTool(tool)
        } label: {
            toolMenuLabel(tool)
        }
    }
    
    @ViewBuilder
    private func activeShape() -> some View {
        if let tool = toolState.activatedTool,
           tool != .cursor {
            toolMenuLabel(tool)
        } else {
            Label(.localizable(.toolbarShapes), systemSymbol: .squareOnCircle)
        }
    }

    @ViewBuilder
    private func toolMenuLabel(_ tool: ExcalidrawTool) -> some View {
        Label {
            Text(tool.localization)
        } icon: {
            Image(systemSymbol: tool.menuSystemSymbol)
        }
    }
    
    
    @ViewBuilder
    private func moreTools() -> some View {
        ExcalidrawToolbarMoreToolsMenu()
    }
}

#if os(iOS)
private enum ExcalidrawToolbarSurfaceShape {
    case circle
    case capsule
    
    var horizontalPadding: CGFloat {
        switch self {
            case .circle:
                6
            case .capsule:
                6
        }
    }
    
    var verticalPadding: CGFloat {
        switch self {
            case .circle:
                6
            case .capsule:
                2
        }
    }
}

private struct ExcalidrawToolbarSurfaceModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    
    let shape: ExcalidrawToolbarSurfaceShape
    
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, shape.horizontalPadding)
            .padding(.vertical, shape.verticalPadding)
            .background {
                surfaceBackground
            }
            .compositingGroup()
            .shadow(
                color: shadowColor,
                radius: shadowRadius,
                x: 0,
                y: shadowYOffset
            )
    }
    
    @ViewBuilder
    private var surfaceBackground: some View {
        switch shape {
            case .circle:
                if #available(iOS 26.0, *) {
                    Circle()
                        .fill(.clear)
                        .glassEffect(.clear, in: Circle())
                } else {
                    Circle()
                        .fill(.regularMaterial)
                }
            case .capsule:
                if #available(iOS 26.0, *) {
                    Capsule()
                        .fill(.clear)
                        .glassEffect(.clear, in: Capsule())
                } else {
                    Capsule()
                        .fill(.regularMaterial)
                }
        }
    }
    
    private var shadowColor: Color {
        guard #available(iOS 26.0, *),
              colorScheme == .light else {
            return .clear
        }
        return .black.opacity(0.08)
    }
    
    private var shadowRadius: CGFloat {
        guard #available(iOS 26.0, *),
              colorScheme == .light else {
            return 0
        }
        return 10
    }
    
    private var shadowYOffset: CGFloat {
        guard #available(iOS 26.0, *),
              colorScheme == .light else {
            return 0
        }
        return 4
    }
}

private extension View {
    func excalidrawToolbarSurface(_ shape: ExcalidrawToolbarSurfaceShape) -> some View {
        modifier(ExcalidrawToolbarSurfaceModifier(shape: shape))
    }
}
#endif

struct ExcalidrawToolbarToolContainer<Content: View>: View {
    @Environment(\.containerSize) private var containerSize
    @EnvironmentObject private var layoutState: LayoutState
    @EnvironmentObject private var fileState: FileState

    var content: (_ size: ExcalidrawToolbarToolSizeClass) -> Content

    init(
        @ViewBuilder content: @escaping (_ size: ExcalidrawToolbarToolSizeClass) -> Content
    ) {
        self.content = content
    }

    var body: some View {
        content(sizeClass)
    }

    private var sizeClass: ExcalidrawToolbarToolSizeClass {
        guard containerSize.width > 0 else { return .dense }

        return ExcalidrawToolbarLayoutPolicy.toolSizeClass(
            for: containerSize.width,
            isSidebarPresented: layoutState.isSidebarPresented,
            isInspectorPresented: layoutState.isInspectorPresented,
            isCollaborationFile: {
                if case .collaborationFile = fileState.currentActiveFile {
                    return true
                }
                return false
            }()
        )
    }
}

struct SegmentedToolPickerItemView: View {
    var tool: ExcalidrawTool
    var size: CGFloat
    var withFooter: Bool
    var shortcutLabel: String?
    
    init(
        tool: ExcalidrawTool,
        size: CGFloat,
        withFooter: Bool,
        shortcutLabel: String? = nil
    ) {
        self.tool = tool
        self.size = size
        self.withFooter = withFooter
        self.shortcutLabel = shortcutLabel
    }
    
    /// Padding behavior for the icon container — Path/SVG-style icons use less internal padding.
    private var labelType: ExcalidrawToolbarItemModifer.LabelType {
        switch tool {
            case .rectangle, .diamond, .ellipse, .line:
                return .nativeShape
            case .cursor:
                return .svg
            default:
                return .image
        }
    }
    
    var body: some View {
        tool.icon()
            .modifier(
                ExcalidrawToolbarItemModifer(size: size, labelType: labelType) {
                    if withFooter, let shortcutLabel {
                        Text(shortcutLabel)
                    }
                }
            )
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

struct CursorModeTrailingButton: View {
    @Environment(\.alertToast) private var alertToast
    
    @ObservedObject var coordinator: ExcalidrawCanvasView.Coordinator
    var onDone: () -> Void
    
    private var hasSelection: Bool {
        !coordinator.selectedElementIDs.isEmpty
    }
    
    var body: some View {
        Button(role: hasSelection ? .destructive : nil) {
            if hasSelection {
                deleteSelectedElements()
            } else {
                onDone()
            }
        } label: {
            if hasSelection {
                Label(.localizable(.generalButtonDelete), systemSymbol: .trash)
                    .labelStyle(.iconOnly)
                    .foregroundStyle(.red)
            } else {
                Text(.localizable(.generalButtonDone))
            }
        }
        .contentTransition(.opacity)
        .animation(.smooth, value: hasSelection)
    }
    
    private func deleteSelectedElements() {
        Task { @MainActor in
            do {
                try await coordinator.toggleDeleteAction()
                coordinator.clearSelectedElementIDs()
            } catch {
                alertToast(error)
            }
        }
    }
}

#Preview {
    ExcalidrawToolbar()
        .background(.background)
}
