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
                    // Render at higher resolution for better clarity
                    GeometryReader { geometry in
                        let renderScale: CGFloat = 3.0

                        canvasView()
                            .frame(
                                width: geometry.size.width * renderScale,
                                height: geometry.size.height * renderScale
                            )
                            .scaleEffect(1.0 / renderScale, anchor: .center)
                            .frame(
                                width: geometry.size.width,
                                height: geometry.size.height
                            )
                    }
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
                                    context.opacity = excalidrawGenericElement.opacity

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
                                            lineWidth: excalidrawGenericElement.strokeWidth * widthScaleEffect,
                                            dash: excalidrawGenericElement.strokeStyle == .solid ? [] : [5]
                                        )
                                    )
                                }
                            case .diamond:
                                context.drawLayer { context in
                                    context.opacity = excalidrawGenericElement.opacity

                                    let diamondPath = Path { path in
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
                                    }

                                    if excalidrawGenericElement.backgroundColor != "transparent" {
                                        context.fill(
                                            diamondPath,
                                            with: .color(Color(excalidrawString: excalidrawGenericElement.backgroundColor))
                                        )
                                    }

                                    context.stroke(
                                        diamondPath,
                                        with: .color(Color(excalidrawString: excalidrawGenericElement.strokeColor)),
                                        style: StrokeStyle(
                                            lineWidth: excalidrawGenericElement.strokeWidth * widthScaleEffect,
                                            dash: excalidrawGenericElement.strokeStyle == .solid ? [] : [5]
                                        )
                                    )
                                }
                            case .ellipse:
                                context.drawLayer { context in
                                    context.opacity = excalidrawGenericElement.opacity

                                    if excalidrawGenericElement.backgroundColor != "transparent" {
                                        context.fill(
                                            Path(ellipseIn: transformedRect),
                                            with: .color(
                                                Color(excalidrawString: excalidrawGenericElement.backgroundColor)
                                            )
                                        )
                                    }

                                    context.stroke(
                                        Path(ellipseIn: transformedRect),
                                        with: .color(Color(excalidrawString: excalidrawGenericElement.strokeColor)),
                                        style: StrokeStyle(
                                            lineWidth: excalidrawGenericElement.strokeWidth * widthScaleEffect,
                                            dash: excalidrawGenericElement.strokeStyle == .solid ? [] : [5]
                                        )
                                    )
                                }
                            default:
                                break
                        }
                    case .text(let excalidrawTextElement):
                        context.drawLayer { context in
                            context.opacity = excalidrawTextElement.opacity
                            let text = Text(excalidrawTextElement.text)
                                .font(.system(size: excalidrawTextElement.fontSize * widthScaleEffect * 0.8))
                                .foregroundColor(Color(excalidrawString: excalidrawTextElement.strokeColor))
                            context.draw(context.resolve(text), in: transformedRect)
                        }
                        
                    case .linear(let excalidrawLinearElement):
                        guard excalidrawLinearElement.points.count > 1 else { break }
                        context.drawLayer { context in
                            context.opacity = excalidrawLinearElement.opacity

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
                                with: .color(Color(excalidrawString: excalidrawLinearElement.strokeColor)),
                                style: StrokeStyle(
                                    lineWidth: excalidrawLinearElement.strokeWidth * widthScaleEffect,
                                    dash: excalidrawLinearElement.strokeStyle == .solid ? [] : [5]
                                )
                            )
                        }
                    case .arrow(let excalidrawArrowElement):
                        guard excalidrawArrowElement.points.count > 1 else { break }
                        context.drawLayer { context in
                            context.opacity = excalidrawArrowElement.opacity

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
                                with: .color(Color(excalidrawString: excalidrawArrowElement.strokeColor)),
                                style: StrokeStyle(
                                    lineWidth: excalidrawArrowElement.strokeWidth * widthScaleEffect,
                                    lineCap: .round,
                                    lineJoin: .round,
                                    dash: excalidrawArrowElement.strokeStyle == .solid ? [] : [5]
                                )
                            )

                            // Draw arrow head at the end
                            if let lastPoint = excalidrawArrowElement.points.last,
                               excalidrawArrowElement.points.count >= 2 {
                                let secondLastPoint = excalidrawArrowElement.points[excalidrawArrowElement.points.count - 2]
                                let endPoint = makePointInCanvas(
                                    point: CGPoint(x: excalidrawArrowElement.x + lastPoint.x,
                                                   y: excalidrawArrowElement.y + lastPoint.y),
                                    canvasSize: size
                                )
                                let prevPoint = makePointInCanvas(
                                    point: CGPoint(x: excalidrawArrowElement.x + secondLastPoint.x,
                                                   y: excalidrawArrowElement.y + secondLastPoint.y),
                                    canvasSize: size
                                )

                                // Calculate arrow head angle
                                let angle = atan2(endPoint.y - prevPoint.y, endPoint.x - prevPoint.x)
                                let arrowHeadLength = 10.0 * widthScaleEffect
                                let arrowHeadAngle = Double.pi / 6

                                context.stroke(
                                    Path { path in
                                        path.move(to: endPoint)
                                        path.addLine(to: CGPoint(
                                            x: endPoint.x - arrowHeadLength * cos(angle - arrowHeadAngle),
                                            y: endPoint.y - arrowHeadLength * sin(angle - arrowHeadAngle)
                                        ))
                                        path.move(to: endPoint)
                                        path.addLine(to: CGPoint(
                                            x: endPoint.x - arrowHeadLength * cos(angle + arrowHeadAngle),
                                            y: endPoint.y - arrowHeadLength * sin(angle + arrowHeadAngle)
                                        ))
                                    },
                                    with: .color(Color(excalidrawString: excalidrawArrowElement.strokeColor)),
                                    style: StrokeStyle(
                                        lineWidth: excalidrawArrowElement.strokeWidth * widthScaleEffect,
                                        lineCap: .round
                                    )
                                )
                            }
                        }
                    case .freeDraw(let excalidrawFreeDrawElement):
                        guard excalidrawFreeDrawElement.points.count > 1 else { break }
                        context.drawLayer { context in
                            context.opacity = excalidrawFreeDrawElement.opacity

                            let rotationCenter = makePointInCanvas(
                                point: CGPoint(x: (excalidrawFreeDrawElement.x + excalidrawFreeDrawElement.points[0].x),
                                               y: (excalidrawFreeDrawElement.y + excalidrawFreeDrawElement.points[0].y)),
                                canvasSize: size
                            )
                            context.translateBy(x: rotationCenter.x, y: rotationCenter.y)
                            context.rotate(by: .radians(excalidrawFreeDrawElement.angle))
                            context.translateBy(x: -rotationCenter.x, y: -rotationCenter.y)

                            context.stroke(
                                Path { path in
                                    path.move(to: rotationCenter)
                                    for point in excalidrawFreeDrawElement.points.suffix(excalidrawFreeDrawElement.points.count - 1) {
                                        path.addLine(to: makePointInCanvas(
                                            point: CGPoint(x: (excalidrawFreeDrawElement.x + point.x),
                                                           y: (excalidrawFreeDrawElement.y + point.y)),
                                            canvasSize: size
                                        ))
                                    }
                                },
                                with: .color(Color(excalidrawString: excalidrawFreeDrawElement.strokeColor)),
                                style: StrokeStyle(
                                    lineWidth: excalidrawFreeDrawElement.strokeWidth * widthScaleEffect,
                                    lineCap: .round,
                                    lineJoin: .round
                                )
                            )
                        }
                    case .draw/*(let excalidrawDrawElement)*/:
                        // Legacy v1 format, can be ignored for now
                        break
                    case .image(let excalidrawImageElement):
                        if let fileID = excalidrawImageElement.fileId {
                            context.drawLayer { context in
                                context.opacity = excalidrawImageElement.opacity
                                renderExcalidrawImage(
                                    context: context,
                                    fileID: fileID,
                                    file: file,
                                    rect: transformedRect
                                )
                            }
                        }
                    case .pdf(let excalidrawPdfElement):
                        // Render PDF as placeholder with page info
                        context.drawLayer { context in
                            context.opacity = excalidrawPdfElement.opacity

                            // Background
                            context.fill(
                                Path(roundedRect: transformedRect, cornerRadius: 4),
                                with: .color(.gray.opacity(0.1))
                            )

                            // Border
                            context.stroke(
                                Path(roundedRect: transformedRect, cornerRadius: 4),
                                with: .color(.gray),
                                style: StrokeStyle(lineWidth: 2, dash: [5, 5])
                            )

                            // PDF icon and text
                            let iconSize: CGFloat = min(transformedRect.width * 0.3, transformedRect.height * 0.3, 40)
                            let iconRect = CGRect(
                                x: transformedRect.midX - iconSize / 2,
                                y: transformedRect.midY - iconSize,
                                width: iconSize,
                                height: iconSize
                            )

                            // Simple PDF icon (rectangle with folded corner)
                            context.stroke(
                                Path(roundedRect: iconRect, cornerRadius: 2),
                                with: .color(.red),
                                style: StrokeStyle(lineWidth: 2)
                            )

                            // Page info text
                            let pageText = "PDF\nPage \(excalidrawPdfElement.currentPage)/\(excalidrawPdfElement.totalPages)"
                            let text: Text = if #available(macOS 14.0, iOS 17.0, *) {
                                Text(pageText)
                                    .font(.system(size: min(transformedRect.width * 0.08, 12)))
                                    .foregroundStyle(.gray)
                                    // .multilineTextAlignment(.center)
                            } else {
                                Text(pageText)
                                    .font(.system(size: min(transformedRect.width * 0.08, 12)))
                                    .foregroundColor(.gray)
                            }
                            context.draw(
                                context.resolve(text),
                                in: CGRect(
                                    x: transformedRect.minX,
                                    y: transformedRect.midY + iconSize / 2,
                                    width: transformedRect.width,
                                    height: transformedRect.height / 3
                                )
                            )
                        }
                    case .frameLike:
                        // Frame elements are usually just containers, render as dashed border
                        break
                    case .iframeLike:
                        // IFrame elements need special handling, show placeholder
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
