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
    
    var minWidth: CGFloat {
        if #available(macOS 13.0, *) {
            if layoutState.isInspectorPresented,
               layoutState.isSidebarPresented {
                return 1480
            } else if layoutState.isSidebarPresented {
                return 1300
            } else if layoutState.isInspectorPresented {
                return 1400
            } else {
                return 1150
            }
        } else {
            return 1150
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
    
    @State private var isApplePencilDisconnectConfirmationDialogPresented = false
    
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
                content(size: layoutState.isExcalidrawToolbarDense ? 14 : 20, withFooter: false)
                Button {
                    isApplePencilDisconnectConfirmationDialogPresented.toggle()
                } label: {
                    if #available(iOS 17.0, *) {
                        Label("Apple Pencil", systemSymbol: .applepencilTip)
                    } else {
                        Label("Apple Pencil", systemSymbol: .applepencil)
                    }
                }
                .confirmationDialog(
                    .localizable(.toolbarApplePencilConnectedTitle),
                    isPresented: $isApplePencilDisconnectConfirmationDialogPresented,
                    titleVisibility: .visible
                ) {
                    Button(role: .destructive) {
                        Task {
                            do {
                                try await toolState.excalidrawWebCoordinator?.togglePenMode(enabled: false)
                                toolState.inPenMode = false
                                try await toolState.excalidrawWebCoordinator?.toggleToolbarAction(key: "h")
                            } catch {
                                alertToast(error)
                            }
                        }
                    } label: {
                        Label(.localizable(.toolbarApplePencilButtonDisconnect), systemSymbol: .pencilSlash)
                            .labelStyle(.titleAndIcon)
                    }
                } message: {
                    Text(.localizable(.toolbarApplePencilConnectedMessage))
                    .multilineTextAlignment(.leading)
                }
                
            }
        }
#elseif os(macOS)
        if layoutState.isExcalidrawToolbarDense {
            denseContent()
        } else {
            content()
        }
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
                    Image(systemSymbol: .wandAndRaysInverse)
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
                Text("Edit")
            }
            .opacity(0)
            Spacer()
            Text("View mode")
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
                Text("Edit")
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
                Label("Cancel", systemSymbol: .xmark)
            }
        } else {
            Button {
                toolState.activatedTool = .freedraw
            } label: {
                Label("Free draw", systemSymbol: .pencilAndOutline)
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
                    Label(.localizable(.toolbarEllipse), systemSymbol: .ellipsis)
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
            } label: {
                if toolState.activatedTool == .cursor {
                    Label("Shapes", systemSymbol: .squareOnCircle)
                } else {
                    activeShape()
                        .foregroundStyle(Color.accentColor)
                }
            }
#if os(iOS)
            .menuOrder(.fixed)
#endif
            Spacer()
            Button {
                toolState.activatedTool = .text
            } label: {
                Label(.localizable(.toolbarText), systemSymbol: .characterTextbox)
            }
            Spacer()
            Button {
                toolState.activatedTool = .image
            } label: {
                Label(.localizable(.toolbarInsertImage), systemSymbol: .photoOnRectangle)
            }
            Spacer()
            if toolState.activatedTool == .cursor {
                Button {
                    Task {
                        try? await toolState.excalidrawWebCoordinator?.toggleToolbarAction(key: "h")
                    }
                } label: {
                    Text("Done")
                }
            } else {
                Button {
                    toolState.activatedTool = .cursor
                } label: {
                    Text("Cancel")
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
