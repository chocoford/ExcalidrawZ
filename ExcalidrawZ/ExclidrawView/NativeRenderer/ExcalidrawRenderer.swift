//
//  ExcalidrawRenderer.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 2024/10/9.
//

import SwiftUI

import ChocofordUI

struct ExcalidrawRenderer: View {
    @Environment(\.colorScheme) var colorScheme
        
    var file: ExcalidrawFile
    var elements: [ExcalidrawElement] {
        file.elements
    }
    
    @State private var frame: CGRect = .zero
    
    var body: some View {
        ZStack {
            if colorScheme == .light {
                content()
            } else {
                content()
                    .colorInvert()
                    .hueRotation(Angle(degrees: 180))
            }
        }
        .onAppear {
            calculateFrame()
        }
    }
    
    @MainActor @ViewBuilder
    private func content() -> some View {
        if frame != .zero {
            Color(excalidrawString: file.appState.viewBackgroundColor ?? "transparent")
                .overlay {
                    canvasView()
                        .aspectRatio(frame.width / frame.height, contentMode: .fit)
                }
        }
    }
    
    @MainActor @ViewBuilder
    private func canvasView() -> some View {
        Canvas(rendersAsynchronously: true) { context, size in
            var widthScaleEffect: CGFloat { size.width / self.frame.width }
            var heightScaleEffect: CGFloat { size.height / self.frame.height }
            for element in elements {
                let transformedRect = CGRect(
                    x: (element.x - frame.minX) * widthScaleEffect,
                    y: (element.y - frame.minY) * heightScaleEffect,
                    width: element.width * widthScaleEffect,
                    height: element.height * heightScaleEffect
                )
                
                switch element {
                    case .generic(let excalidrawGenericElement):
                        switch excalidrawGenericElement.type {
                            case .selection:
                                break
                            case .rectangle:
                                context.drawLayer { context in
                                    
                                    let rotationCenter = transformedRect.origin
                                    context.translateBy(x: rotationCenter.x, y: rotationCenter.y)
                                    context.rotate(by: .radians(excalidrawGenericElement.angle))
                                    context.translateBy(x: -rotationCenter.x, y: -rotationCenter.y)
                                    
                                    if excalidrawGenericElement.backgroundColor != "transparent" {
                                        context.fill(
                                            Path(
                                                roundedRect: transformedRect,
                                                cornerRadius: getCornerRadius(
                                                    element: excalidrawGenericElement,
                                                    scaleEffect: (widthScaleEffect, heightScaleEffect)
                                                )
                                            ),
                                            with:  .color(Color(excalidrawString: excalidrawGenericElement.backgroundColor))
                                        )
                                    }
                                    
                                    context.stroke(
                                        Path(
                                            roundedRect: transformedRect,
                                            cornerRadius: getCornerRadius(
                                                element: excalidrawGenericElement,
                                                scaleEffect: (widthScaleEffect, heightScaleEffect)
                                            )
                                        ),
                                        with: .color(Color(excalidrawString: excalidrawGenericElement.strokeColor)),
                                        style: StrokeStyle(
                                            lineWidth: excalidrawGenericElement.strokeWidth,
                                            dash: excalidrawGenericElement.strokeStyle == .solid ? [] : [5]
                                        )
                                    )
                                    
 
                                }
                            case .diamond:
                                context.stroke(
                                    Path { path in
                                        path.move(to: makePointInCanvas(
                                            point: CGPoint(x: excalidrawGenericElement.x,
                                                           y: excalidrawGenericElement.y + excalidrawGenericElement.height / 2),
                                            canvasSize: size
                                        ))
                                        path.addLine(to: makePointInCanvas(
                                            point: CGPoint(x: excalidrawGenericElement.x + excalidrawGenericElement.width / 2,
                                                           y: excalidrawGenericElement.y),
                                            canvasSize: size))
                                        path.addLine(to: makePointInCanvas(
                                            point: CGPoint(x: excalidrawGenericElement.x + excalidrawGenericElement.width,
                                                           y: excalidrawGenericElement.y + excalidrawGenericElement.height / 2),
                                            canvasSize: size
                                        ))
                                        
                                        path.addLine(to: makePointInCanvas(
                                            point: CGPoint(x: excalidrawGenericElement.x + excalidrawGenericElement.width / 2,
                                                           y: excalidrawGenericElement.y + excalidrawGenericElement.height),
                                            canvasSize: size
                                        ))
                                        path.closeSubpath()
                                    },
                                    with: .color(Color(excalidrawString: excalidrawGenericElement.strokeColor)),
                                    lineWidth: excalidrawGenericElement.strokeWidth
                                )
                                break
                            case .ellipse:
                                context.drawLayer { context in
                                    if excalidrawGenericElement.backgroundColor != "transparent" {
                                        context.fill(
                                            Path(ellipseIn: transformedRect),
                                            with: .color(
                                                Color(excalidrawString: excalidrawGenericElement.backgroundColor)
                                            )
                                        )
                                    }
                                    
                                    context.stroke(
                                        Path(ellipseIn: transformedRect ),
                                        with: .color(Color(excalidrawString: excalidrawGenericElement.strokeColor)),
                                        lineWidth: excalidrawGenericElement.strokeWidth
                                    )
                                }
                            default:
                                break
                        }
                    case .text(let excalidrawTextElement):
                        context.drawLayer { context in
                            context.draw(
                                Text(excalidrawTextElement.text)
                                    .font(.system(size: excalidrawTextElement.fontSize * widthScaleEffect * 0.8))
                                    .foregroundColor(Color(excalidrawString: excalidrawTextElement.strokeColor)),
                                in: transformedRect
                            )
                        }
                        
                    case .linear(let excalidrawLinearElement):
                        guard excalidrawLinearElement.points.count > 1 else { break }
                        context.drawLayer { context in
                            let rotationCenter = makePointInCanvas(
                                point: CGPoint(x: (excalidrawLinearElement.x + excalidrawLinearElement.points[0].x),
                                               y: (excalidrawLinearElement.y + excalidrawLinearElement.points[0].y)),
                                canvasSize: size
                            )
                            context.translateBy(x: rotationCenter.x, y: rotationCenter.y)
                            context.rotate(by: .radians(excalidrawLinearElement.angle))
                            context.translateBy(x: -rotationCenter.x, y: -rotationCenter.y)
                            
                            context.stroke(
                                Path { path in
                                    path.move(to:rotationCenter)
                                    for point in excalidrawLinearElement.points.suffix(excalidrawLinearElement.points.count - 1) {
                                        path.addLine(to: makePointInCanvas(
                                            point: CGPoint(x: (excalidrawLinearElement.x + point.x),
                                                           y: (excalidrawLinearElement.y + point.y)),
                                            canvasSize: size
                                        ))
                                    }
                                    
                                },
                                with: .color(.black)
                            )
                        }
                    case .arrow(let excalidrawArrowElement):
                        guard excalidrawArrowElement.points.count > 1 else { break }
                        context.drawLayer { context in
                            let rotationCenter = makePointInCanvas(
                                point: CGPoint(x: (excalidrawArrowElement.x + excalidrawArrowElement.points[0].x),
                                               y: (excalidrawArrowElement.y + excalidrawArrowElement.points[0].y)),
                                canvasSize: size
                            )
                            context.translateBy(x: rotationCenter.x, y: rotationCenter.y)
                            context.rotate(by: .radians(excalidrawArrowElement.angle))
                            context.translateBy(x: -rotationCenter.x, y: -rotationCenter.y)
                            
                            context.stroke(
                                Path { path in
                                    path.move(to:rotationCenter)
                                    for point in excalidrawArrowElement.points.suffix(excalidrawArrowElement.points.count - 1) {
                                        path.addLine(to: makePointInCanvas(
                                            point: CGPoint(x: (excalidrawArrowElement.x + point.x),
                                                           y: (excalidrawArrowElement.y + point.y)),
                                            canvasSize: size
                                        ))
                                    }
                                    
                                },
                                with: .color(.black)
                            )
                        }
                    case .freeDraw/*(let excalidrawFreeDrawElement)*/:
                        break
                    case .draw/*(let excalidrawDrawElement)*/:
                        break
                    case .image(let excalidrawImageElement):
                        if let fileID = excalidrawImageElement.fileId {
                            renderExcalidrawImage(
                                context: context,
                                fileID: fileID,
                                file: file,
                                rect: transformedRect
                            )
                        }
                    case .frame:
                        break
                    case .iframeLike:
                        break
                }
            }
        }
    }
    
    private func makePointInCanvas(point: CGPoint, canvasSize: CGSize) -> CGPoint {
        CGPoint(
            x: (point.x - self.frame.minX) * canvasSize.width / (self.frame.maxX - self.frame.minX),
            y: (point.y - self.frame.minY) * canvasSize.height / (self.frame.maxY - self.frame.minY)
        )
    }
    
    private func calculateFrame() {
        self.frame = self.elements.reduce(.zero) { partialResult, element in
            CGRect(
                x: min(partialResult.minX, element.x),
                y: min(partialResult.minY, element.y),
                width: max(partialResult.maxX - partialResult.minX, element.x + element.width),
                height: max(partialResult.maxY - partialResult.minY, element.y + element.height)
            )
        }
    }
    
    /// From excalidraw - packages/excalidraw/math.ts
    private func getCornerRadius(element: ExcalidrawGenericElement, scaleEffect: (CGFloat, CGFloat)) -> CGFloat {
        /// packages/excalidraw/constants.ts - 322
        let defaultPropotionalRadius = 0.25
        /// packages/excalidraw/constants.ts - 324
        let defaultAdaptiveRadius: Double = 32
        
        let x = min(element.width * scaleEffect.0, element.height * scaleEffect.1)
        
        if element.roundness?.type == .legacy || element.roundness?.type == .proportionalRadius {
            return x * defaultPropotionalRadius
        }
        
        if element.roundness?.type == .adaptiveRadius {
            let fixedRadiusSize = element.roundness?.value ?? defaultAdaptiveRadius
            
            let cutoffSize = fixedRadiusSize / defaultPropotionalRadius
            
            if x <= cutoffSize {
                return x * defaultPropotionalRadius
            }
            
            return fixedRadiusSize
        }
        
        return 0
        
    }

}

extension Color {
    init(excalidrawString string: String) {
        if string.hasPrefix("#") {
            self.init(hexString: string)
        } else if string == "transparent" {
            self = .clear
        } else {
            self = .clear
        }
    }
}


#if DEBUG
#Preview {
    let file: ExcalidrawFile = try! JSONDecoder().decode(
        ExcalidrawFile.self,
        from: Data(contentsOf: Bundle.main.url(forResource: "Groundwater UI.excalidraw", withExtension: nil)!)
    )
    ExcalidrawRenderer(file: file)
}
#endif
