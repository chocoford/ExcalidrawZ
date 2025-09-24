//
//  BeforeAfterSlider.swift
//  ExcalidrawZ
//
//  Created by Chocoford on 9/16/25.
//

import SwiftUI
import Vortex

struct BeforeAfterSlider<First: View, Second: View, Handle: View>: View {
    enum SlideMode { case hover, drag }
    
    let firstContent: First
    let secondContent: Second
    let handle: Handle
    
    var slideMode: SlideMode = .hover
    var showHandlebar: Bool = true
    var initialPercentage: CGFloat = 0.5 // 0~1
    var autoplay: Bool = false
    var autoplayDuration: Double = 10.0
    
    @State private var sliderPercentage: CGFloat
    @State private var isDragging = false
    @State private var isMouseOver = false
    @State private var isAutoplaying = false
    @State private var direction: CGFloat = 1
    
//    let sliderParticles: VortexSystem = {
////        Emitter()
////            .emissionRate(20)
////            .lifetime(2)
////            .spread(.degrees(90))   // 左右散开
////            .speed(80)
////            .position(.zero)
//        
//        Particle()
//            .shape(.circle)
//            .color(.blue)
//            .size(2)
//            .opacity(0.8)
//            .fadeOut(0.5)
//    }()
    
    init(
        slideMode: SlideMode = .hover,
        showHandlebar: Bool = true,
        initialPercentage: CGFloat = 0.5,
        autoplay: Bool = false,
        autoplayDuration: Double = 5.0,
        @ViewBuilder firstContent: () -> First,
        @ViewBuilder secondContent: () -> Second,
        @ViewBuilder handle: () -> Handle
    ) {
        self.slideMode = slideMode
        self.showHandlebar = showHandlebar
        self.initialPercentage = initialPercentage
        self.autoplay = autoplay
        self.autoplayDuration = autoplayDuration
        self.firstContent = firstContent()
        self.secondContent = secondContent()
        self.handle = handle()
        _sliderPercentage = State(initialValue: initialPercentage)
    }
    
    var body: some View {
        VortexViewReader { proxy in
            GeometryReader { geo in
                ZStack {
                    // 底层 → 第二张永远铺满
                    secondContent
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipped()
                        .mask {
                            HStack {
                                Spacer(minLength: 0)
                                Rectangle()
                                    .frame(
                                        width: geo.size.width * (1 - sliderPercentage),
                                        height: geo.size.height
                                    )
                            }
                        }
                    
                    // 上层 → 第一张裁切
                    firstContent
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipped()
                        .mask {
                            HStack {
                                Rectangle()
                                    .frame(
                                        width: geo.size.width * sliderPercentage,
                                        height: geo.size.height
                                    )
                                Spacer(minLength: 0)
                            }
                        }
                    
                    // 中间线
                    Rectangle()
                        .fill(LinearGradient(colors: [.clear, .blue, .clear],
                                             startPoint: .top, endPoint: .bottom))
                        .frame(width: 2)
                        .position(
                            x: geo.size.width * sliderPercentage,
                            y: geo.size.height / 2
                        )
                    
                    VortexView(createSnow()) {
                        Circle()
                            .fill(.cyan)
                            .blur(radius: 2)
                            .frame(width: 6)
                            .tag("particle")
                    }
                    .offset(x: geo.size.width * (sliderPercentage - 0.5))
                    
                    // Handle
                    if showHandlebar {
                        handle
                            .frame(width: 30, height: 30)
                            .background(Color.white)
                            .clipShape(Circle())
                            .shadow(radius: 2)
                            .position(x: geo.size.width * sliderPercentage,
                                      y: geo.size.height / 2)
                            .gesture(
                                DragGesture()
                                    .onChanged { value in
                                        if slideMode == .drag {
                                            stopAutoplay()
                                            updatePercentage(x: value.location.x, width: geo.size.width)
                                        }
                                    }
                            )
                    }
                }
                .contentShape(Rectangle())
                .onHover { inside in
                    if slideMode == .hover {
                        isMouseOver = inside
                        if !inside {
                            withAnimation {
                                sliderPercentage = initialPercentage
                            }
                        }
                    }
                }
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            if slideMode == .hover || slideMode == .drag {
                                stopAutoplay()
                                updatePercentage(x: value.location.x, width: geo.size.width)
                            }
                        }
                )
                .onAppear {
                    if autoplay {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                            startAutoplay()
                        }
                    }
                }
                .onDisappear { stopAutoplay() }
            }
        }
    }
    
    private func updatePercentage(x: CGFloat, width: CGFloat) {
        sliderPercentage = max(0, min(1, x / width))
    }
    
    func startAutoplay() {
        isAutoplaying = true
        
        let target: CGFloat = direction > 0 ? 1 : 0
        
        withAnimation(.linear(duration: autoplayDuration)) {
            sliderPercentage = target
        }
        
        // 动画结束后 + 停顿
        DispatchQueue.main.asyncAfter(deadline: .now() + autoplayDuration + 1.5) {
            guard isAutoplaying else { return } // 用户打断就直接退出
            direction *= -1
            startAutoplay()
        }
    }

    func stopAutoplay() {
        isAutoplaying = false
    }
    
    private func createSnow() -> VortexSystem {
        let system = VortexSystem(tags: ["particle"])
                
        // 整条竖线作为发射区域
        system.position = [0.5, 0.5]          // 在父视图中点
        system.shape = .box(width: 0, height: 1) // 垂直发射区域
        
        // 粒子运动
        system.speed = 0.1
        system.speedVariation = 0.2
        system.lifespan = 2
        system.angle = .degrees(0)
        system.angleRange = .degrees(360)
        
        // 粒子外观
        system.size = 0.2
        system.sizeVariation = 0.3
//        system.spin = 0.5
//        system.alpha = 0.8
//        system.alphaVariation = 0.2
        
        return system
    }
}


#Preview {
    BeforeAfterSlider(
        slideMode: .drag,
        showHandlebar: true,
        initialPercentage: 0.5,
        autoplay: true,
        autoplayDuration: 5
    ) {
        Image("ExcalidrawZ - Old")
            .resizable()
            .scaledToFit()
    } secondContent: {
        Image("ExcalidrawZ - New")
            .resizable()
            .scaledToFit()
    } handle: {
        Image(systemName: "line.horizontal.3")
            .foregroundColor(.black)
    }
    
}
