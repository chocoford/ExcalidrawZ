//
//  RootView.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 2024/7/25.
//

import SwiftUI
import Logging

let debugLogger = Logger(label: "DEBUG")

/// Don't do any other actions in this view.
struct RootView: View {
    var body: some View {
        ContentView()
    }
}

@available(iOS 18.0, macOS 15.0, *)
struct TestView: View {
    
    var aspectioes: [CGFloat] {
        [
            0.125,
            0.5,
            1.0,
            0.125,
            8.0,
        ]
    }
        
    @State private var scrollPosition: ScrollPosition = .init(idType: Int.self)
    var currentIndex: Int {
        scrollPosition.viewID(type: Int.self) ?? -1
    }
    
    var body: some View {
        VStack {
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 0) {
                    ForEach(0..<10, id: \.self) { i in
                        HStack {
                            RoundedRectangle(cornerRadius: 12)
                                .fill(.red)
                                .aspectRatio(aspectioes[i % 5], contentMode: .fit)
                        }
                        .containerRelativeFrame(.horizontal)
                        .scrollTransition(.interactive, axis: .horizontal) { content, phase in
                            content
                                .scaleEffect(phase.isIdentity ? 1.0 : 0.9)
                        }
                    }
                }
                .scrollTargetLayout()
            }
            .scrollPosition($scrollPosition)
            .contentMargins(.horizontal, 30, for: .scrollContent)
            .scrollClipDisabled()
            .scrollTargetBehavior(.viewAligned)
         
            Text(currentIndex.formatted())
        }
    }
}

#Preview {
    if #available(iOS 18.0, macOS 15.0, *) {
        TestView()
    } else {
        // Fallback on earlier versions
    }
}
