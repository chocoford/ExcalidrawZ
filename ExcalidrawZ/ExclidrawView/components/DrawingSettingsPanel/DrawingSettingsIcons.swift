//
//  DrawingSettingsIcons.swift
//  ExcalidrawZ
//
//  Created by Chocoford on 1/5/26.
//

import SwiftUI


// MARK: Fill

struct FillHachureIcon: View {
    
    static let viewBox = CGRect(x: 0.0, y: 0.0, width: 20, height: 20)
    
    struct PathView1: View { // SVGPath
        
        struct PathShape1: Shape {
            
            func path(in rect: CGRect) -> Path {
                Path { path in
                    path.move(to: CGPoint(x: 5.879, y: 2.625))
                    path.addLine(to: CGPoint(x: 14.121, y: 2.625))
                    path.addRelativeArc(center: CGPoint(x: 0, y: 0), radius: 1, startAngle: Angle(radians: -1.5708), delta: Angle(radians: 1.5708), transform: CGAffineTransform(translationX: 14.121, y: 5.879)
                        .scaledBy(x: 3.254, y: 3.254)
                    )
                    path.addLine(to: CGPoint(x: 17.375, y: 14.121))
                    path.addRelativeArc(center: CGPoint(x: 0, y: 0), radius: 1, startAngle: Angle(radians: 0), delta: Angle(radians: 1.5708), transform: CGAffineTransform(translationX: 14.121, y: 14.121)
                        .scaledBy(x: 3.254, y: 3.254)
                    )
                    path.addLine(to: CGPoint(x: 5.88, y: 17.375))
                    path.addRelativeArc(center: CGPoint(x: 0, y: 0), radius: 1, startAngle: Angle(radians: 1.5708), delta: Angle(radians: 1.5708), transform: CGAffineTransform(translationX: 5.88, y: 14.121)
                        .scaledBy(x: 3.254, y: 3.254)
                    )
                    path.addLine(to: CGPoint(x: 2.626, y: 5.88))
                    path.addRelativeArc(center: CGPoint(x: 0, y: 0), radius: 1, startAngle: Angle(radians: 3.1416), delta: Angle(radians: 1.5708), transform: CGAffineTransform(translationX: 5.88, y: 5.88)
                        .scaledBy(x: 3.254, y: 3.254)
                    )
                    path.closeSubpath()
                }
            }
        }
        
        var body: some View {
            PathShape1()
                .stroke(Color(white: 0), style: StrokeStyle(lineWidth: 1.25))
        }
    }
    
    struct PathView2: View { // SVGPath
        
        struct PathShape2: Shape {
            
            func path(in rect: CGRect) -> Path {
                Path { path in
                    path.move(to: CGPoint(x: 5.879, y: 2.625))
                    path.addLine(to: CGPoint(x: 14.121, y: 2.625))
                    path.addRelativeArc(center: CGPoint(x: 0, y: 0), radius: 1, startAngle: Angle(radians: -1.5708), delta: Angle(radians: 1.5708), transform: CGAffineTransform(translationX: 14.121, y: 5.879)
                        .scaledBy(x: 3.254, y: 3.254)
                    )
                    path.addLine(to: CGPoint(x: 17.375, y: 14.121))
                    path.addRelativeArc(center: CGPoint(x: 0, y: 0), radius: 1, startAngle: Angle(radians: 0), delta: Angle(radians: 1.5708), transform: CGAffineTransform(translationX: 14.121, y: 14.121)
                        .scaledBy(x: 3.254, y: 3.254)
                    )
                    path.addLine(to: CGPoint(x: 5.88, y: 17.375))
                    path.addRelativeArc(center: CGPoint(x: 0, y: 0), radius: 1, startAngle: Angle(radians: 1.5708), delta: Angle(radians: 1.5708), transform: CGAffineTransform(translationX: 5.88, y: 14.121)
                        .scaledBy(x: 3.254, y: 3.254)
                    )
                    path.addLine(to: CGPoint(x: 2.626, y: 5.88))
                    path.addRelativeArc(center: CGPoint(x: 0, y: 0), radius: 1, startAngle: Angle(radians: 3.1416), delta: Angle(radians: 1.5708), transform: CGAffineTransform(translationX: 5.88, y: 5.88)
                        .scaledBy(x: 3.254, y: 3.254)
                    )
                    path.closeSubpath()
                }
            }
        }
        
        var body: some View {
            ZStack {
                PathShape2()
                    .fill(Color(white: 0))
                PathShape2()
                    .stroke(Color(white: 0), style: StrokeStyle(lineWidth: 1.25))
            }
        }
    }
    
    struct Group1: View {
        
        struct PathView3: View { // SVGPath
            
            struct PathShape3: Shape {
                
                func path(in rect: CGRect) -> Path {
                    Path { path in
                        path.move(to: CGPoint(x: 2.258, y: 15.156))
                        path.addLine(to: CGPoint(x: 15.156, y: 2.258))
                        path.move(to: CGPoint(x: 7.324, y: 20.222))
                        path.addLine(to: CGPoint(x: 20.222, y: 7.325))
                        path.move(to: CGPoint(x: -0.222, y: 12.675))
                        path.addLine(to: CGPoint(x: 12.675, y: -0.222))
                        path.move(to: CGPoint(x: 4.518, y: 18.118))
                        path.addLine(to: CGPoint(x: 17.416, y: 5.22))
                    }
                }
            }
            
            var body: some View {
                PathShape3()
                    .stroke(Color(white: 0), style: StrokeStyle(lineWidth: 1.25, lineCap: .round, lineJoin: .round))
            }
        }
        
        var body: some View {
            PathView3()
        }
    }
    
    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                PathView1()
                PathView2()
                Group1()
            }
            .frame(width: Self.viewBox.width, height: Self.viewBox.height,
                   alignment: .topLeading)
            .scaleEffect(
                x: proxy.size.width  / Self.viewBox.width,
                y: proxy.size.height / Self.viewBox.height
            )
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
    }
}


struct FillCrossHatchIcon: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let width = rect.size.width
        let height = rect.size.height
        path.move(to: CGPoint(x: 0.29395*width, y: 0.13125*height))
        path.addLine(to: CGPoint(x: 0.70605*width, y: 0.13125*height))
        path.addLine(to: CGPoint(x: 0, y: 0.70605*height))
        path.addLine(to: CGPoint(x: 0.294*width, y: 0))
        path.addLine(to: CGPoint(x: 0, y: 0.294*height))
        path.closeSubpath()
        path.move(to: CGPoint(x: 0.70605*width, y: 0.1*height))
        path.addLine(to: CGPoint(x: 0.294*width, y: 0.1*height))
        path.addLine(to: CGPoint(x: 0, y: 0.70605*height))
        path.addLine(to: CGPoint(x: 0.70605*width, y: 0))
        path.addLine(to: CGPoint(x: 0, y: 0.294*height))
        path.closeSubpath()
        return path
    }
}

struct FillSolidIcon: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let width = rect.size.width
        let height = rect.size.height
        path.move(to: CGPoint(x: 0.00959*width, y: 0.00513*height))
        path.addLine(to: CGPoint(x: 0.02947*width, y: 0.00513*height))
        path.addLine(to: CGPoint(x: 0, y: 0.02947*height))
        path.addLine(to: CGPoint(x: 0.00959*width, y: 0))
        path.addLine(to: CGPoint(x: 0, y: 0.00959*height))
        path.closeSubpath()
        return path
    }
}

// MARK: - Sloppiness

struct SloppinessArchitectIcon: View {
    
    static let viewBox = CGRect(x: 0.0, y: 0.0, width: 20, height: 20)
    
    struct PathView1: View { // SVGPath
        
        struct PathShape1: Shape {
            
            func path(in rect: CGRect) -> Path {
                Path { path in
                    path.move(to: CGPoint(x: 2.5, y: 12.038))
                    path.addCurve(to: CGPoint(x: 11.068, y: 7.684),
                                  control1: CGPoint(x: 4.155, y: 11.153),
                                  control2: CGPoint(x: 8.4, y: 8.746))
                    path.addCurve(to: CGPoint(x: 12.388, y: 10.788),
                                  control1: CGPoint(x: 13.736, y: 6.621),
                                  control2: CGPoint(x: 11.169, y: 10.505))
                    path.addCurve(to: CGPoint(x: 17.5, y: 8.974),
                                  control1: CGPoint(x: 13.606, y: 11.071),
                                  control2: CGPoint(x: 17.5, y: 8.974))
                }
            }
        }
        
        var body: some View {
            PathShape1()
                .stroke(.primary, style: StrokeStyle(lineWidth: 1.25))
        }
    }
    
    var body: some View {
        GeometryReader { proxy in
            PathView1()
                .frame(width: Self.viewBox.width, height: Self.viewBox.height,
                       alignment: .topLeading)
                .scaleEffect(x: proxy.size.width  / Self.viewBox.width,
                             y: proxy.size.height / Self.viewBox.height)
                .frame(width: proxy.size.width, height: proxy.size.height)
        }
    }
}

struct SloppinessArtistIcon: View {
    static let viewBox = CGRect(x: 0.0, y: 0.0, width: 20, height: 20)
    
    struct PathView1: View { // SVGPath
        
        struct PathShape1: Shape {
            
            func path(in rect: CGRect) -> Path {
                Path { path in
                    path.move(to: CGPoint(x: 2.5, y: 12.563))
                    path.addCurve(to: CGPoint(x: 11.068, y: 8.208),
                                  control1: CGPoint(x: 4.155, y: 11.677),
                                  control2: CGPoint(x: 8.4, y: 9.27))
                    path.addCurve(to: CGPoint(x: 12.388, y: 11.313),
                                  control1: CGPoint(x: 13.736, y: 7.146),
                                  control2: CGPoint(x: 11.169, y: 11.03))
                    path.addCurve(to: CGPoint(x: 17.5, y: 9.499),
                                  control1: CGPoint(x: 13.606, y: 11.596),
                                  control2: CGPoint(x: 17.5, y: 9.499))
                    path.move(to: CGPoint(x: 4.031, y: 11.729))
                    path.addCurve(to: CGPoint(x: 11.499, y: 6.731),
                                  control1: CGPoint(x: 6.994, y: 10.143),
                                  control2: CGPoint(x: 10.161, y: 6.109))
                    path.addCurve(to: CGPoint(x: 11.367, y: 12.326),
                                  control1: CGPoint(x: 12.837, y: 7.354),
                                  control2: CGPoint(x: 10.346, y: 10.841))
                    path.addCurve(to: CGPoint(x: 17.5, y: 10.896),
                                  control1: CGPoint(x: 12.387, y: 13.813),
                                  control2: CGPoint(x: 17.5, y: 10.896))
                }
            }
        }
        
        var body: some View {
            PathShape1()
                .stroke(.primary, style: StrokeStyle(lineWidth: 1.25))
        }
    }
    
    var body: some View {
        GeometryReader { proxy in
            PathView1()
                .frame(width: Self.viewBox.width, height: Self.viewBox.height,
                       alignment: .topLeading)
                .scaleEffect(x: proxy.size.width  / Self.viewBox.width,
                             y: proxy.size.height / Self.viewBox.height)
                .frame(width: proxy.size.width, height: proxy.size.height)
        }
    }
}

struct SloppinessCartoonistIcon: View {
    
    static let viewBox = CGRect(x: 0.0, y: 0.0, width: 20, height: 20)
    
    struct PathView1: View { // SVGPath
        
        struct PathShape1: Shape {
            
            func path(in rect: CGRect) -> Path {
                Path { path in
                    path.move(to: CGPoint(x: 2.5, y: 11.936))
                    path.addCurve(to: CGPoint(x: 12.92, y: 6.668),
                                  control1: CGPoint(x: 4.237, y: 11.057),
                                  control2: CGPoint(x: 11.127, y: 6.59))
                    path.addCurve(to: CGPoint(x: 13.265, y: 12.404),
                                  control1: CGPoint(x: 14.715, y: 6.746),
                                  control2: CGPoint(x: 12.502, y: 11.806))
                    path.addCurve(to: CGPoint(x: 17.5, y: 10.257),
                                  control1: CGPoint(x: 14.028, y: 13.002),
                                  control2: CGPoint(x: 16.795, y: 10.615))
                    path.move(to: CGPoint(x: 2.929, y: 9.788))
                    path.addCurve(to: CGPoint(x: 9.916, y: 6.674),
                                  control1: CGPoint(x: 4.093, y: 9.269),
                                  control2: CGPoint(x: 8.399, y: 6.508))
                    path.addCurve(to: CGPoint(x: 12.037, y: 10.783),
                                  control1: CGPoint(x: 11.435, y: 6.839),
                                  control2: CGPoint(x: 10.916, y: 10.501))
                    path.addCurve(to: CGPoint(x: 16.643, y: 8.363),
                                  control1: CGPoint(x: 13.159, y: 11.064),
                                  control2: CGPoint(x: 15.876, y: 8.767))
                }
            }
        }
        
        var body: some View {
            PathShape1()
                .stroke(.primary, style: StrokeStyle(lineWidth: 1.25))
        }
    }
    
    var body: some View {
        GeometryReader { proxy in
            PathView1()
                .frame(width: Self.viewBox.width, height: Self.viewBox.height,
                       alignment: .topLeading)
                .scaleEffect(x: proxy.size.width  / Self.viewBox.width,
                             y: proxy.size.height / Self.viewBox.height)
                .frame(width: proxy.size.width, height: proxy.size.height)
        }
    }
}


// MARK: - Edge

struct EdgeSharpIcon: View {
    
    static let viewBox = CGRect(x: 0.0, y: 0.0, width: 20, height: 20)
    
    struct Group1: View {
        
        struct PathView1: View { // SVGPath
            
            struct PathShape1: Shape {
                
                func path(in rect: CGRect) -> Path {
                    Path { path in
                        path.move(to: CGPoint(x: 3.3333, y: 10))
                        path.addLine(to: CGPoint(x: 3.3333, y: 6.6666))
                        path.addCurve(to: CGPoint(x: 3.3354, y: 3.3365),
                                      control1: CGPoint(x: 3.3333, y: 6.0433),
                                      control2: CGPoint(x: 3.334, y: 4.9332))
                        path.addCurve(to: CGPoint(x: 6.6667, y: 3.3333),
                                      control1: CGPoint(x: 4.9523, y: 3.3344),
                                      control2: CGPoint(x: 6.0628, y: 3.3333))
                        path.addLine(to: CGPoint(x: 10, y: 3.3333))
                    }
                }
            }
            
            var body: some View {
                PathShape1()
                    .stroke(Color(white: 0), style: StrokeStyle(lineWidth: 1.5))
            }
        }
        
        struct PathView2: View { // SVGPath
            
            struct PathShape2: Shape {
                
                func path(in rect: CGRect) -> Path {
                    Path { path in
                        path.move(to: CGPoint(x: 13.3333, y: 3.3333))
                        path.addLine(to: CGPoint(x: 13.3333, y: 3.3433))
                    }
                }
            }
            
            var body: some View {
                PathShape2()
                    .stroke(Color(white: 0), style: StrokeStyle(lineWidth: 1.5))
            }
        }
        
        struct PathView3: View { // SVGPath
            
            struct PathShape3: Shape {
                
                func path(in rect: CGRect) -> Path {
                    Path { path in
                        path.move(to: CGPoint(x: 16.6667, y: 3.3333))
                        path.addLine(to: CGPoint(x: 16.6667, y: 3.3433))
                    }
                }
            }
            
            var body: some View {
                PathShape3()
                    .stroke(Color(white: 0), style: StrokeStyle(lineWidth: 1.5))
            }
        }
        
        struct PathView4: View { // SVGPath
            
            struct PathShape4: Shape {
                
                func path(in rect: CGRect) -> Path {
                    Path { path in
                        path.move(to: CGPoint(x: 16.6667, y: 6.6667))
                        path.addLine(to: CGPoint(x: 16.6667, y: 6.6767))
                    }
                }
            }
            
            var body: some View {
                PathShape4()
                    .stroke(Color(white: 0), style: StrokeStyle(lineWidth: 1.5))
            }
        }
        
        struct PathView5: View { // SVGPath
            
            struct PathShape5: Shape {
                
                func path(in rect: CGRect) -> Path {
                    Path { path in
                        path.move(to: CGPoint(x: 16.6667, y: 10))
                        path.addLine(to: CGPoint(x: 16.6667, y: 10.01))
                    }
                }
            }
            
            var body: some View {
                PathShape5()
                    .stroke(Color(white: 0), style: StrokeStyle(lineWidth: 1.5))
            }
        }
        
        struct PathView6: View { // SVGPath
            
            struct PathShape6: Shape {
                
                func path(in rect: CGRect) -> Path {
                    Path { path in
                        path.move(to: CGPoint(x: 3.3333, y: 13.3333))
                        path.addLine(to: CGPoint(x: 3.3333, y: 13.3433))
                    }
                }
            }
            
            var body: some View {
                PathShape6()
                    .stroke(Color(white: 0), style: StrokeStyle(lineWidth: 1.5))
            }
        }
        
        struct PathView7: View { // SVGPath
            
            struct PathShape7: Shape {
                
                func path(in rect: CGRect) -> Path {
                    Path { path in
                        path.move(to: CGPoint(x: 16.6667, y: 13.3333))
                        path.addLine(to: CGPoint(x: 16.6667, y: 13.3433))
                    }
                }
            }
            
            var body: some View {
                PathShape7()
                    .stroke(Color(white: 0), style: StrokeStyle(lineWidth: 1.5))
            }
        }
        
        struct PathView8: View { // SVGPath
            
            struct PathShape8: Shape {
                
                func path(in rect: CGRect) -> Path {
                    Path { path in
                        path.move(to: CGPoint(x: 3.3333, y: 16.6667))
                        path.addLine(to: CGPoint(x: 3.3333, y: 16.6767))
                    }
                }
            }
            
            var body: some View {
                PathShape8()
                    .stroke(Color(white: 0), style: StrokeStyle(lineWidth: 1.5))
            }
        }
        
        struct PathView9: View { // SVGPath
            
            struct PathShape9: Shape {
                
                func path(in rect: CGRect) -> Path {
                    Path { path in
                        path.move(to: CGPoint(x: 6.6667, y: 16.6667))
                        path.addLine(to: CGPoint(x: 6.6667, y: 16.6767))
                    }
                }
            }
            
            var body: some View {
                PathShape9()
                    .stroke(Color(white: 0), style: StrokeStyle(lineWidth: 1.5))
            }
        }
        
        struct PathView10: View { // SVGPath
            
            struct PathShape10: Shape {
                
                func path(in rect: CGRect) -> Path {
                    Path { path in
                        path.move(to: CGPoint(x: 10, y: 16.6667))
                        path.addLine(to: CGPoint(x: 10, y: 16.6767))
                    }
                }
            }
            
            var body: some View {
                PathShape10()
                    .stroke(Color(white: 0), style: StrokeStyle(lineWidth: 1.5))
            }
        }
        
        struct PathView11: View { // SVGPath
            
            struct PathShape11: Shape {
                
                func path(in rect: CGRect) -> Path {
                    Path { path in
                        path.move(to: CGPoint(x: 13.3333, y: 16.6667))
                        path.addLine(to: CGPoint(x: 13.3333, y: 16.6767))
                    }
                }
            }
            
            var body: some View {
                PathShape11()
                    .stroke(Color(white: 0), style: StrokeStyle(lineWidth: 1.5))
            }
        }
        
        struct PathView12: View { // SVGPath
            
            struct PathShape12: Shape {
                
                func path(in rect: CGRect) -> Path {
                    Path { path in
                        path.move(to: CGPoint(x: 16.6667, y: 16.6667))
                        path.addLine(to: CGPoint(x: 16.6667, y: 16.6767))
                    }
                }
            }
            
            var body: some View {
                PathShape12()
                    .stroke(Color(white: 0), style: StrokeStyle(lineWidth: 1.5))
            }
        }
        
        var body: some View {
            ZStack(alignment: .topLeading) {
                SwiftUI.Group {
                    PathView1()
                    PathView2()
                    PathView3()
                    PathView4()
                    PathView5()
                    PathView6()
                    PathView7()
                    PathView8()
                    PathView9()
                }
                SwiftUI.Group {
                    PathView10()
                    PathView11()
                    PathView12()
                }
            }
        }
    }
    
    var body: some View {
        GeometryReader { proxy in
            Group1()
                .frame(width: Self.viewBox.width, height: Self.viewBox.height,
                       alignment: .topLeading)
                .scaleEffect(x: proxy.size.width  / Self.viewBox.width,
                             y: proxy.size.height / Self.viewBox.height)
                .frame(width: proxy.size.width, height: proxy.size.height)
        }
    }
    
}

struct EdgeRoundIcon: Shape {
    nonisolated func path(in rect: CGRect) -> Path {
        var path = Path()
        let width = rect.size.width
        let height = rect.size.height
        path.move(to: CGPoint(x: 0, y: 0))
        path.addLine(to: CGPoint(x: width, y: 0))
        path.addLine(to: CGPoint(x: width, y: height))
        path.addLine(to: CGPoint(x: 0, y: height))
        path.closeSubpath()
        path.move(to: CGPoint(x: 0.16667*width, y: 0.5*height))
        path.addLine(to: CGPoint(x: 0.16667*width, y: 0.33333*height))
        path.addLine(to: CGPoint(x: 0.5*width, y: 0))
        return path
    }
}


#Preview {
    HStack {
        
    }
}
