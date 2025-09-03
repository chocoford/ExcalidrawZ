//
//  AutoFitVideoPlayer.swift
//  ExcalidrawZ
//
//  Created by Chocoford on 9/1/25.
//

import SwiftUI
import AVKit

import ChocofordUI

struct AutoContainVideoPlayer: View {
    var url: URL
    
    var baseAxis: Axis = .horizontal
    
    init(url: URL, baseAxis: Axis = .horizontal) {
        self.url = url
        self.baseAxis = baseAxis
    }
    
    @State private var videoDimension: CGSize?
    @State private var error: Error?
    
    var body: some View {
        ZStack {
            if let videoDimension {
                VideoPlayer(
                    player: AVPlayer(
                        url: url
                    )
                )
                .scaleToContain(baseAxis: baseAxis, orginSize: videoDimension)
            } else if let error {
                Color.gray
                    .overlay {
                        Text(error.localizedDescription)
                            .font(.footnote.italic())
                            .foregroundStyle(.red)
                            .padding(40)
                            .multilineTextAlignment(.center)
                    }
            } else {
                Color.black
                    .frame(height: 300)
                    .onAppear {
                        getVideoDimensions(url: url)
                    }
            }
        }
    }
    
    private func getVideoDimensions(url: URL) {
        self.error = nil
        let asset = AVURLAsset(url: url)
        
        Task.detached {
            do {
                if let track = try await asset.loadTracks(withMediaType: .video).first {
                    let size = try await track.load(.naturalSize)
                    
                    let transform = try await track.load(.preferredTransform)
                    let realSize = size.applying(transform)
                    
                    let width = abs(realSize.width)
                    let height = abs(realSize.height)
                    
                    await MainActor.run {
                        self.videoDimension = CGSize(width: width, height: height)
                    }
                }
            } catch {
                await MainActor.run {
                    self.error = error
                }
            }
        }
    }
}


struct AutoFitModifier: ViewModifier {
    var defatultLength: CGFloat?
    var orginSize: () -> CGSize?
    var baseAxis: Axis = .horizontal
    
    public init(
        baseAxis: Axis,
        defatultLength: CGFloat?,
        orginSize: @autoclosure @escaping () -> CGSize?
    ) {
        self.baseAxis = baseAxis
        self.defatultLength = defatultLength
        self.orginSize = orginSize
        
        self._displayWidth = State(initialValue: baseAxis == .vertical ? defatultLength : nil)
        self._displayHeight = State(initialValue: baseAxis == .horizontal ? defatultLength : nil)
    }
    
//    public init(baseAxis: Axis, orginSize: @autoclosure @escaping () -> CGSize) {
//        self.baseAxis = baseAxis
//        self.orginSize = orginSize
//    }

    @State private var width: CGFloat?
    @State private var height: CGFloat?
    @State private var displayWidth: CGFloat?
    @State private var displayHeight: CGFloat?
    
    func body(content: Content) -> some View {
        content
            .readSize(width: $width, height: $height)
            .frame(width: displayWidth, height: displayHeight)
            .watchImmediately(of: width) { _ in
                if baseAxis == .horizontal {
                    calSize()
                }
            }
            .watchImmediately(of: height) { _ in
                if baseAxis == .vertical {
                    calSize()
                }
            }
    }
    
    private func calSize() {
        // get video dimension
        guard let dimension = orginSize() else { return }
        
        switch baseAxis {
            case .horizontal:
                guard let width else { return }
                let aspectRatio = dimension.width / dimension.height
                displayHeight = width / aspectRatio
                
            case .vertical:
                guard let height else { return }
                let aspectRatio = dimension.width / dimension.height
                displayWidth = height * aspectRatio
        }
    }

}


extension View {
    @ViewBuilder
    public func scaleToContain(
        baseAxis: Axis = .horizontal,
        defatultLength: CGFloat? = nil,
        orginSize: @autoclosure @escaping () -> CGSize?
    ) -> some View {
        modifier(
            AutoFitModifier(
                baseAxis: baseAxis,
                defatultLength: defatultLength,
                orginSize: orginSize()
            )
        )
    }
}
