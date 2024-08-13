//
//  LoadingView.swift
//  CSWang
//
//  Created by Dove Zachary on 2022/12/2.
//

import SwiftUI

struct LoadingView<Content: View, S: ShapeStyle>: View {
    var progress: Float
    var indeterminate: Bool
    
    var size: CGFloat
    var lineWidth: CGFloat
    var strokeColor: S
    
    var content: ((_ progress: Int) -> Content)?
    
    @State private var loading: Bool = false
    @State private var degree: CGFloat = 0
    
    @State private var trimLength: CGFloat = 0

    @State private var indeterminateLoading = true
    @State private var isProgessReady = false
    
    @State private var progressValue: Int = 0
    @State private var progressTimer: Timer? = nil

    init(size: CGFloat = 50, lineWidth: CGFloat = 4, progress: Float? = nil) where Content == EmptyView, S == LinearGradient {
        self.init(size: size,
                  lineWidth: lineWidth,
                  progress: progress,
                  strokeColor: LinearGradient(gradient: Gradient(colors: [Color(#colorLiteral(red: 0.9568627477, green: 0.6588235497, blue: 0.5450980663, alpha: 1)), Color(#colorLiteral(red: 0.8549019694, green: 0.250980407, blue: 0.4784313738, alpha: 1))]),
                                              startPoint: .topTrailing,
                                              endPoint: .bottomLeading)) { progress in
            EmptyView()
        }
    }
    
    init(size: CGFloat = 50, lineWidth: CGFloat = 4, progress: Float? = nil, strokeColor: S) where Content == EmptyView {
        self.init(size: size,
                  lineWidth: lineWidth,
                  progress: progress,
                  strokeColor: strokeColor) { progress in
            EmptyView()
        }
    }

    init(size: CGFloat = 50, lineWidth: CGFloat = 4, progress: Float? = nil,
         @ViewBuilder content: @escaping (_ progress: Int) -> Content) where S == LinearGradient {
        self.init(size: size,
                  lineWidth: lineWidth,
                  progress: progress,
                  strokeColor: LinearGradient(gradient: Gradient(colors: [Color(#colorLiteral(red: 0.9568627477, green: 0.6588235497, blue: 0.5450980663, alpha: 1)), Color(#colorLiteral(red: 0.8549019694, green: 0.250980407, blue: 0.4784313738, alpha: 1))]),
                                              startPoint: .topTrailing,
                                              endPoint: .bottomLeading)) { progress in
            content(progress)
        }
    }
    
    init(size: CGFloat = 50, lineWidth: CGFloat = 4, progress: Float? = nil, strokeColor: S,
         @ViewBuilder content: @escaping (_ progress: Int) -> Content) {
        self.content = content
        self.size = size
        self.progress = progress ?? 0
        self.indeterminate = progress == nil
        self.lineWidth = lineWidth
        self.strokeColor = strokeColor
    }

    var animationDuration: Double = 0.8
    
    var rotatingAnimation: Animation {
        Animation.linear(duration: animationDuration)
            .repeatForever(autoreverses: false)
    }
    
    var trimAnimation: Animation {
        Animation.easeInOut(duration: animationDuration)
            .repeatForever(autoreverses: true)
    }
    
    var body: some View {
        ZStack {
            if indeterminateLoading {
                Circle()
                    .trim(from: 0.2 + trimLength, to: 1 - trimLength)
                    .stroke(
                        strokeColor,
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                    )
                    .frame(width: size, height: size)
                    .rotationEffect(Angle(degrees: degree))
                    .onAppear {
                        withAnimation(rotatingAnimation) {
                            degree = 360
                        }
                        withAnimation(trimAnimation) {
                            trimLength = 0.38
                        }
                    }
            } else {
                ZStack {
                    Circle()
                        .stroke(
                            Color.gray.opacity(0.5),
                            lineWidth: lineWidth
                        )
                    
                    Circle()
                        .trim(from: 0, to: CGFloat(progress))
                        .stroke(
                            strokeColor,
                            style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                        )
                        .rotationEffect(Angle(degrees: -90))
                    
                }
                .animation(.linear(duration: 0.5), value: progress)
                .frame(width: size, height: size)
                .onAppear {
                    isProgessReady = true
                }
            }
            if let content = content {
                content(progressValue)
            }
            
        }
        .onChange(of: progress) { p in
            if p > 0 {
                indeterminateLoading = false
            } else if indeterminateLoading {
                var localProgrss: Float = Float(self.progressValue)
                self.progressTimer?.invalidate()
                let difference = 100 * p - localProgrss
                /// 默认500ms
                self.progressTimer = Timer.scheduledTimer(withTimeInterval: 0.01, repeats: true) { timer in
                    localProgrss += difference / 50
                    self.progressValue = Int(localProgrss)
                    if localProgrss >= 100 * p {
                        timer.invalidate()
                    }
                }
            }
        }
    }
}

struct DefaultLoadingView<Content: View>: View {
    var progress: Float? = nil
    var content: ((_ progress: Int) -> Content)?

    init(progress: Float? = nil) where Content == EmptyView {
        self.content = nil
        self.progress = 0
    }

    init(progress: Float? = nil, @ViewBuilder content: @escaping (_ progress: Int) -> Content) {
        self.content = content
        self.progress = progress ?? 0
    }

    var body: some View {
        mainView
    }
    
    @ViewBuilder private var mainView: some View {
        if let content = content {
            LoadingView(size: 50, lineWidth: 4, progress: progress,
                        strokeColor: LinearGradient(gradient: Gradient(colors: [Color(#colorLiteral(red: 0.9568627477, green: 0.6588235497, blue: 0.5450980663, alpha: 1)), Color(#colorLiteral(red: 0.8549019694, green: 0.250980407, blue: 0.4784313738, alpha: 1))]),
                                                    startPoint: .topTrailing,
                                                    endPoint: .bottomLeading)) { progress in
                content(progress)
            }
        } else {
            LoadingView(size: 50, lineWidth: 4, progress: progress,
                        strokeColor: LinearGradient(gradient: Gradient(colors: [Color(#colorLiteral(red: 0.9568627477, green: 0.6588235497, blue: 0.5450980663, alpha: 1)), Color(#colorLiteral(red: 0.8549019694, green: 0.250980407, blue: 0.4784313738, alpha: 1))]),
                                                    startPoint: .topTrailing,
                                                    endPoint: .bottomLeading))
        }
    }
}

struct LoadingView_Previews: PreviewProvider {
    static var previews: some View {
        DefaultLoadingView()
    }
}
