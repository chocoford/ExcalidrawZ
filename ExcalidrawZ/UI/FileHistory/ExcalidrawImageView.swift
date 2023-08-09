//
//  ExcalidrawImageView.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 2023/8/6.
//

import SwiftUI

struct ExcalidrawImageView: View {
    var data: Data?
    
    @State private var elements: [ExcalidrawElement] = []
    
    @State var minX: Double = 0
    @State var minY: Double = 0
    @State var maxX: Double = 800
    @State var maxY: Double = 600
    
    var body: some View {
        Canvas(rendersAsynchronously: true) { context, size in
            var widthScaleEffect: CGFloat {  size.width / (self.maxX - self.minX) }
            var heightScaleEffect: CGFloat {  size.height / (self.maxY - self.minY) }
            
            for element in elements {
                switch element {
                    case .generic(let excalidrawGenericElement):
                        switch excalidrawGenericElement {
                            case .selection(let excalidrawSelectionElement):
                                break
                            case .rectangle(let excalidrawRectangleElement):
                                context.stroke(
                                    Path(
                                        roundedRect: CGRect(
                                            from: excalidrawRectangleElement,
                                            minX: minX,
                                            minY: minY,
                                            widthScaleEffect: widthScaleEffect,
                                            heightScaleEffect: heightScaleEffect
                                        ),
                                        cornerRadius: excalidrawRectangleElement.roundness?.type == .adaptiveRadius ? 8 : excalidrawRectangleElement.roundness?.value ?? 0
                                    ),
                                    with: .color(Color(hexString: excalidrawRectangleElement.strokeColor)),
                                    lineWidth: excalidrawRectangleElement.strokeWidth
                                )
                            case .diamond(let excalidrawDiamondElement):
                                context.stroke(
                                    Path { path in
                                        path.move(to: makePointInCanvas(
                                            point: CGPoint(x: excalidrawDiamondElement.x,
                                                           y: excalidrawDiamondElement.y + excalidrawDiamondElement.height / 2),
                                            canvasSize: size
                                        ))
                                        path.addLine(to: makePointInCanvas(
                                            point: CGPoint(x: excalidrawDiamondElement.x + excalidrawDiamondElement.width / 2,
                                                           y: excalidrawDiamondElement.y),
                                            canvasSize: size))
                                        path.addLine(to: makePointInCanvas(
                                            point: CGPoint(x: excalidrawDiamondElement.x + excalidrawDiamondElement.width,
                                                           y: excalidrawDiamondElement.y + excalidrawDiamondElement.height / 2),
                                            canvasSize: size
                                        ))
                                        
                                        path.addLine(to: makePointInCanvas(
                                            point: CGPoint(x: excalidrawDiamondElement.x + excalidrawDiamondElement.width / 2,
                                                           y: excalidrawDiamondElement.y + excalidrawDiamondElement.height),
                                            canvasSize: size
                                        ))
                                        path.closeSubpath()
                                    },
                                    with: .color(Color(hexString: excalidrawDiamondElement.strokeColor)),
                                    lineWidth: excalidrawDiamondElement.strokeWidth
                                )
                                break
                            case .ellipse(let excalidrawEllipseElement):
                                context.stroke(
                                    Path(
                                        ellipseIn: CGRect(
                                            from: excalidrawEllipseElement,
                                            minX: minX,
                                            minY: minY,
                                            widthScaleEffect: widthScaleEffect,
                                            heightScaleEffect: heightScaleEffect
                                        )
                                    ),
                                    with: .color(Color(hexString: excalidrawEllipseElement.strokeColor)),
                                    lineWidth: excalidrawEllipseElement.strokeWidth
                                )
                        }
                        break
                    case .text(let excalidrawTextElement):
                        context.draw(
                            Text(excalidrawTextElement.text)
                                .font(.system(size: excalidrawTextElement.fontSize * widthScaleEffect * 0.8))
                                .foregroundColor(Color(hexString: excalidrawTextElement.strokeColor)),
                            in: CGRect(
                                from: excalidrawTextElement,
                                minX: minX,
                                minY: minY,
                                widthScaleEffect: widthScaleEffect,
                                heightScaleEffect: heightScaleEffect
                            )
                        )
                    case .linear(let excalidrawLinearElement):
                        guard excalidrawLinearElement.points.count > 1 else { break }
                        context.stroke(Path { path in
                            path.move(to: makePointInCanvas(point: CGPoint(x: (excalidrawLinearElement.x + excalidrawLinearElement.points[0].x),
                                                                           y: (excalidrawLinearElement.y + excalidrawLinearElement.points[0].y)),
                                                            canvasSize: size))
                            
                            for point in excalidrawLinearElement.points.suffix(excalidrawLinearElement.points.count - 1) {
                                path.addLine(to: makePointInCanvas(
                                    point: CGPoint(x: (excalidrawLinearElement.x + point.x),
                                                   y: (excalidrawLinearElement.y + point.y)),
                                    canvasSize: size
                                ))
                            }

                        }, with: .color(.black))
                    case .freeDraw(let excalidrawFreeDrawElement):
                        break
                    case .image(let excalidrawImageElement):
                        break
                }
            }
        }
        .background(.white, in: RoundedRectangle(cornerRadius: 8))
        .onAppear(perform: decodeData)
        .overlay(alignment: .bottomTrailing) {
            Image(systemName: "info.circle.fill")
                .foregroundColor(.black)
                .help("Beta · This is rendered by native canvas.")
        }
        .padding()
    }
    
    func decodeData() {
        guard let data = self.data else { return }
        do {
            let jsonObj = try JSONSerialization.jsonObject(with: data) as! [String : Any]
            guard let elementsObj = jsonObj["elements"] else { return }
            let elementsData = try JSONSerialization.data(withJSONObject: elementsObj)
            
            let elements = try JSONDecoder().decode([ExcalidrawElement].self,
                                                      from: elementsData)

            if elements.count > 0 {
                var minX: Double = elements[0].x
                var minY: Double = elements[0].y
                var maxX: Double = elements[0].x
                var maxY: Double = elements[0].y
                for element in elements {
                    minX = min(element.x, minX)
                    minY = min(element.y, minY)
                    maxX = max(element.x + element.width, maxX)
                    maxY = max(element.y + element.height, maxY)
                }
                self.minX = minX
                self.minY = minY
                self.maxX = min(maxX, 1024)
                self.maxY = min(maxY, 1024)
            }
            dump(elements)
            self.minX -= 20
            self.minY -= 20
            self.maxX += 20
            self.maxY += 20
            self.elements = elements
        } catch {
            dump(error)
        }
    }
    
    func makePointInCanvas(point: CGPoint, canvasSize: CGSize) -> CGPoint {
        CGPoint(
            x: (point.x - self.minX) * canvasSize.width / (self.maxX - self.minX),
            y: (point.y - self.minY) * canvasSize.height / (self.maxY - self.minY)
        )
    }
}

fileprivate extension CGRect {
    init<T: ExcalidrawElementBase>(from exclidrawElement: T,
                                   minX: Double,
                                   minY: Double,
                                   widthScaleEffect: Double,
                                   heightScaleEffect: Double) {
        self.init(x: (exclidrawElement.x - minX) * widthScaleEffect,
                  y: (exclidrawElement.y - minY) * heightScaleEffect,
                  width: exclidrawElement.width * widthScaleEffect,
                  height: exclidrawElement.height * heightScaleEffect)
    }
}

#if DEBUG
#Preview {
    ExcalidrawImageView(data: File.preview.content)
}
#endif
