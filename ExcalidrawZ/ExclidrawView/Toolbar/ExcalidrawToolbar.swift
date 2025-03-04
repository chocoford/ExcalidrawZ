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

    var minWidth: CGFloat {
        if #available(macOS 13.0, *) {
            if layoutState.isInspectorPresented,
               layoutState.isSidebarPresented {
                return 1760
            } else if layoutState.isSidebarPresented {
                return 1520
            } else if layoutState.isInspectorPresented {
                return 1620
            } else {
                return 1380
            }
        } else {
            return 1380
        }
    }
    
    var body: some View {
        toolbar()
            .animation(nil, value: layoutState.isExcalidrawToolbarDense)
            .bindWindow($window)
            .onChange(of: window) { newValue in
                guard let newValue else { return }
                layoutState.isExcalidrawToolbarDense = newValue.frame.width < minWidth
                windowFrameCancellable = newValue.publisher(for: \.frame).sink { frame in
                    layoutState.isExcalidrawToolbarDense = newValue.frame.width < self.minWidth
                }
            }
            .onChange(of: layoutState.isSidebarPresented) { _ in
                layoutState.isExcalidrawToolbarDense = (window?.frame.width ?? .zero) < minWidth
            }
            .onChange(of: layoutState.isInspectorPresented) { _ in
                layoutState.isExcalidrawToolbarDense = (window?.frame.width ?? .zero) < minWidth
            }
            .onChange(of: toolState.activatedTool, debounce: 0.05) { newValue in
                if newValue == nil {
                    toolState.activatedTool = .cursor
                }
                
                if let tool = newValue, tool != toolState.excalidrawWebCoordinator?.lastTool {
                    Task {
                        do {
                            if let key = tool.keyEquivalent {
                                try await toolState.excalidrawWebCoordinator?.toggleToolbarAction(key: key)
                            } else if tool == .webEmbed {
                                try await toolState.excalidrawWebCoordinator?.toggleToolbarAction(tool: .webEmbed)
                            } else if tool == .magicFrame {
                                try await toolState.excalidrawWebCoordinator?.toggleToolbarAction(tool: .magicFrame)
                            } else {
                                try await toolState.excalidrawWebCoordinator?.toggleToolbarAction(key: tool.rawValue)
                            }
                        } catch {
                            alertToast(error)
                        }
                    }
                }
            }
    }
    
    @MainActor @ViewBuilder
    private func toolbar() -> some View {
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
        if layoutState.isExcalidrawToolbarDense {
            denseContent()
        } else {
            content()
        }
        
        moreTools()
#endif
    }
    
    @MainActor @ViewBuilder
    private func content(size: CGFloat = 20, withFooter: Bool = true) -> some View {
        HStack(spacing: size / 2) {
            SegmentedPicker(selection: $toolState.activatedTool) {
                SegmentedPickerItem(value: ExcalidrawTool.cursor) {
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
                }
                .help("\(String(localizable: .toolbarSelection)) - V \(String(localizable: .toolbarOr)) 1")
                
                SegmentedPickerItem(value: ExcalidrawTool.rectangle) {
                    RoundedRectangle(cornerRadius: 3)
                        .stroke(.primary, lineWidth: 1.5)
                        .modifier(
                            ExcalidrawToolbarItemModifer(size: size, labelType: .nativeShape) {
                                if withFooter {
                                    Text("2")
                                }
                            }
                        )
                    
                }
                .help("\(String(localizable: .toolbarRectangle)) — R \(String(localizable: .toolbarOr)) 2")
                
                SegmentedPickerItem(value: ExcalidrawTool.diamond) {
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
                }
                .help("\(String(localizable: .toolbarDiamond)) — D \(String(localizable: .toolbarOr)) 3")
                
                SegmentedPickerItem(value: ExcalidrawTool.ellipse) {
                    Circle()
                        .stroke(.primary, lineWidth: 1.5)
                        .modifier(
                            ExcalidrawToolbarItemModifer(size: size, labelType: .nativeShape) {
                                if withFooter {
                                    Text("4")
                                }
                            }
                        )
                }
                .help("\(String(localizable: .toolbarEllipse)) — O \(String(localizable: .toolbarOr)) 4")
                
                SegmentedPickerItem(value: ExcalidrawTool.arrow) {
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
                }
                .help("\(String(localizable: .toolbarArrow)) — A \(String(localizable: .toolbarOr)) 5")
                
                SegmentedPickerItem(value: ExcalidrawTool.line) {
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
                }
                .help("\(String(localizable: .toolbarLine)) — L \(String(localizable: .toolbarOr)) 6")
                
                SegmentedPickerItem(value: ExcalidrawTool.freedraw) {
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
                }
                .help("\(String(localizable: .toolbarDraw)) — P \(String(localizable: .toolbarOr)) 7")
                
                SegmentedPickerItem(value: ExcalidrawTool.text) {
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
                }
                .help("\(String(localizable: .toolbarText)) — T \(String(localizable: .toolbarOr)) 8")
                
                SegmentedPickerItem(value: ExcalidrawTool.image) {
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
                }
                .help("\(String(localizable: .toolbarInsertImage)) — 9")
                
                SegmentedPickerItem(value: ExcalidrawTool.eraser) {
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
                }
                .help("\(String(localizable: .toolbarEraser)) — E \(String(localizable: .toolbarOr)) 0")
                
                SegmentedPickerItem(value: ExcalidrawTool.laser) {
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
                }
                .help("\(String(localizable: .toolbarLaser)) — K")
                
                SegmentedPickerItem(value: ExcalidrawTool.frame) {
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
                }
                .help("\(String(localizable: .toolbarFrame)) - F")
                
                SegmentedPickerItem(value: ExcalidrawTool.webEmbed) {
                    Image(systemSymbol: .chevronLeftForwardslashChevronRight)
                        .resizable()
                        .scaledToFit()
                        .font(.body.weight(.semibold))
                        .modifier(
                            ExcalidrawToolbarItemModifer(size: size, labelType: .image) {}
                        )
                            
                }
                .help("\(String(localizable: .toolbarWebEmbed))")
                
                SegmentedPickerItem(value: ExcalidrawTool.magicFrame) {
                    Image(systemSymbol: .wandAndStarsInverse)
                        .resizable()
                        .scaledToFit()
                        .font(.body.weight(.semibold))
                        .modifier(
                            ExcalidrawToolbarItemModifer(size: size, labelType: .image) {}
                        )
                }
                .help("\(String(localizable: .toolbarMagicFrame))")
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
        }
    }
    
    @MainActor @ViewBuilder
    private func compactContent() -> some View {
        if toolState.inDragMode {
            Button {
            } label: {
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
                Text(.localizable(.toolbarSelection)).tag(ExcalidrawTool.cursor)
                Text(.localizable(.toolbarRectangle)).tag(ExcalidrawTool.rectangle)
                Text(.localizable(.toolbarDiamond)).tag(ExcalidrawTool.diamond)
                Text(.localizable(.toolbarEllipse)).tag(ExcalidrawTool.ellipse)
                Text(.localizable(.toolbarArrow)).tag(ExcalidrawTool.arrow)
                Text(.localizable(.toolbarLine)).tag(ExcalidrawTool.line)
                Text(.localizable(.toolbarDraw)).tag(ExcalidrawTool.freedraw)
                Text(.localizable(.toolbarText)).tag(ExcalidrawTool.text)
                Text(.localizable(.toolbarInsertImage)).tag(ExcalidrawTool.image)
                Text(.localizable(.toolbarEraser)).tag(ExcalidrawTool.eraser)
                Text(.localizable(.toolbarLaser)).tag(ExcalidrawTool.laser)
                Text(.localizable(.toolbarFrame)).tag(ExcalidrawTool.frame)
                Text(.localizable(.toolbarWebEmbed)).tag(ExcalidrawTool.webEmbed)
                Text(.localizable(.toolbarMagicFrame)).tag(ExcalidrawTool.magicFrame)
            } label: {
                Text("Active tool")
            }
            .pickerStyle(.menu)
            .fixedSize()
        }
    }

    @MainActor @ViewBuilder
    private func activeShape() -> some View {
        switch toolState.activatedTool {
            case .rectangle:
                Label("Rectangle", systemSymbol: .rectangle)
            case .diamond:
                Label("Diamond", systemSymbol: .diamond)
            case .ellipse:
                Label("Ellips", systemSymbol: .ellipsis)
            case .arrow:
                Label("Arrow", systemSymbol: .lineDiagonalArrow)
            case .line:
                Label("Line", systemSymbol: .lineDiagonal)
            default:
                Label("Shapes", systemSymbol: .squareOnCircle)
        }
    }
    
    @MainActor @ViewBuilder
    private func moreTools() -> some View {
        Menu {
            Button {
                Task {
                    try? await toolState.excalidrawWebCoordinator?.toggleToolbarAction(tool: .text2Diagram)
                }
            } label: {
                Text(.localizable(.toolbarText2Diagram))
            }
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
                Text("Math")
            }
        } label: {
            if #available(macOS 15.0, iOS 18.0, *) {
                Label(.localizable(.toolbarMoreTools), systemImage: "xmark.triangle.circle.square")
            } else {
                Label(.localizable(.toolbarMoreTools), systemSymbol: .chartXyaxisLine)
            }
        }
        .menuIndicator(.hidden)
#if os(iOS)
        .menuOrder(.fixed)
#endif
        .modifier(
            MathInputSheetViewModifier(isPresented: $isMathInputSheetPresented) {
                
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
