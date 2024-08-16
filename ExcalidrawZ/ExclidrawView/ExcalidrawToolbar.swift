//
//  ExcalidrawToolbar.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 2024/8/10.
//

import SwiftUI
import SFSafeSymbols

struct ExcalidrawToolbar: View {
    @EnvironmentObject var toolState: ToolState
    
    var body: some View {

        HStack(spacing: 10) {
            SegmentedPicker(selection: $toolState.activatedTool) {
                SegmentedPickerItem(value: ExcalidrawTool.cursor) {
                    Cursor()
                        .stroke(.primary, lineWidth: 1.5)
                        .aspectRatio(1, contentMode: .fit)
                        .modifier(
                            ExcalidrawToolbarItemModifer(labelType: .svg) {
                                Text("1")
                            }
                        )
                }
                .help("\(String(localizable: .toolbarSelection)) - V \(String(localizable: .toolbarOr)) 1")
                
                SegmentedPickerItem(value: ExcalidrawTool.rectangle) {
                    RoundedRectangle(cornerRadius: 3)
                        .stroke(.primary, lineWidth: 1.5)
                        .modifier(
                            ExcalidrawToolbarItemModifer(labelType: .nativeShape) {
                                Text("2")
                            }
                        )
                    
                }
                .help("\(String(localizable: .toolbarRectangle)) — R \(String(localizable: .toolbarOr)) 2")
                
                SegmentedPickerItem(value: ExcalidrawTool.diamond) {
                    RoundedRectangle(cornerRadius: 3)
                        .stroke(.primary, lineWidth: 1.5)
                        .rotationEffect(.degrees(45))
                        .modifier(
                            ExcalidrawToolbarItemModifer(labelType: .nativeShape) {
                                Text("3")
                            }
                        )
                }
                .help("\(String(localizable: .toolbarDiamond)) — D \(String(localizable: .toolbarOr)) 3")
                
                SegmentedPickerItem(value: ExcalidrawTool.ellipse) {
                    Circle()
                        .stroke(.primary, lineWidth: 1.5)
                        .modifier(
                            ExcalidrawToolbarItemModifer(labelType: .nativeShape) {
                                Text("4")
                            }
                        )
                }
                .help("\(String(localizable: .toolbarEllipse)) — O \(String(localizable: .toolbarOr)) 4")
                
                SegmentedPickerItem(value: ExcalidrawTool.arrow) {
                    Image(systemSymbol: .arrowRight)
                        .font(.body.weight(.semibold))
                        .modifier(
                            ExcalidrawToolbarItemModifer(labelType: .image) {
                                Text("5")
                            }
                        )
                }
                .help("\(String(localizable: .toolbarArrow)) — A \(String(localizable: .toolbarOr)) 5")
                
                SegmentedPickerItem(value: ExcalidrawTool.line) {
                    Capsule()
                        .stroke(.primary, lineWidth: 1.5)
                        .frame(height: 1)
                        .modifier(
                            ExcalidrawToolbarItemModifer(labelType: .nativeShape) {
                                Text("6")
                            }
                        )
                }
                .help("\(String(localizable: .toolbarLine)) — L \(String(localizable: .toolbarOr)) 6")
                
                SegmentedPickerItem(value: ExcalidrawTool.freedraw) {
                    Image(systemSymbol: .pencil)
                        .font(.body.weight(.semibold))
                        .modifier(
                            ExcalidrawToolbarItemModifer(labelType: .image) {
                                Text("7")
                            }
                        )
                }
                .help("\(String(localizable: .toolbarDraw)) — P \(String(localizable: .toolbarOr)) 7")
                
                SegmentedPickerItem(value: ExcalidrawTool.text) {
                    Image(systemSymbol: .character)
                        .font(.body.weight(.semibold))
                        .modifier(
                            ExcalidrawToolbarItemModifer(labelType: .image) {
                                Text("8")
                            }
                        )
                }
                .help("\(String(localizable: .toolbarText)) — T \(String(localizable: .toolbarOr)) 8")
                
                SegmentedPickerItem(value: ExcalidrawTool.image) {
                    Image(systemSymbol: .photo)
                        .font(.body.weight(.semibold))
                        .modifier(
                            ExcalidrawToolbarItemModifer(labelType: .image) {
                                Text("9")
                            }
                        )
                }
                .help("\(String(localizable: .toolbarInsertImage)) — 9")
                
                SegmentedPickerItem(value: ExcalidrawTool.eraser) {
                    if #available(macOS 13.0, *) {
                        Image(systemSymbol: .eraserLineDashed)
                            .font(.body.weight(.semibold))
                            .modifier(
                                ExcalidrawToolbarItemModifer(labelType: .image) {
                                    Text("0")
                                }
                            )
                    } else {
                        Image(systemSymbol: .pencilSlash)
                            .font(.body.weight(.semibold))
                            .modifier(
                                ExcalidrawToolbarItemModifer(labelType: .image) {
                                    Text("0")
                                }
                            )
                    }
                }
                .help("\(String(localizable: .toolbarEraser)) — E \(String(localizable: .toolbarOr)) 0")
                
                SegmentedPickerItem(value: ExcalidrawTool.laser) {
                    Image(systemSymbol: .wandAndRaysInverse)
                        .font(.body.weight(.semibold))
                        .modifier(
                            ExcalidrawToolbarItemModifer(labelType: .image) {
                                Text("K")
                            }
                        )
                }
                .help("\(String(localizable: .toolbarLaser)) — K")
            }
            .background {
                if #available(macOS 14.0, *) {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(.regularMaterial)
                        .stroke(.separator, lineWidth: 0.5)
                } else {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(.regularMaterial)
                }
            }
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
        labelType: LabelType,
        @ViewBuilder footer: () -> Footer
    ) {
        self.labelType = labelType
        self.footer = AnyView(footer())
    }
    
    let size: CGFloat = 20
    
    func body(content: Content) -> some View {
        content
            .padding(labelType == .nativeShape ? 4 : labelType == .svg ? 0 : 6)
            .aspectRatio(1, contentMode: .fit)
            .frame(width: size, height: size)
            .padding(4)
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
