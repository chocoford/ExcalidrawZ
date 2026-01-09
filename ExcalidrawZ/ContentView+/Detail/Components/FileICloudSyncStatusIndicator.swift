//
//  FileICloudSyncStatusIndicator.swift
//  ExcalidrawZ
//
//  Created by Chocoford on 1/3/26.
//

import SwiftUI

#if os(iOS)
/// A View only for showing syncing status
struct FileICloudSyncStatusIndicator: View {
    var file: FileState.ActiveFile
    
    @State private var fileStatus: FileStatus? = nil
    var body: some View {
        ZStack {
            if #available(macOS 26.0, iOS 26.0, *) {
                ZStack {
                    if fileStatus?.iCloudStatus == .syncing {
                        Image(systemSymbol: .arrowTrianglehead2ClockwiseRotate90Icloud)
                            .drawOnAppear(options: .speed(2))
                    } else {
                        Image(systemSymbol: .checkmarkIcloud)
                            .drawOnAppear(options: .speed(2))
                            .foregroundStyle(.green)
                    }
                }
            } else {
                if fileStatus?.iCloudStatus == .syncing {
                    if #available(macOS 15.0, iOS 18.0, *) {
                        Image(systemSymbol: .arrowTrianglehead2ClockwiseRotate90Icloud)
                    } else {
                        Image(systemSymbol: .arrowTriangle2Circlepath)
                    }
                } else if case .downloaded = fileStatus?.iCloudStatus {
                    Image(systemSymbol: .checkmarkIcloud)
                        .foregroundStyle(.green)
                }
            }
        }
        .bindFileStatus(for: file, status: $fileStatus)
        .symbolRenderingMode(.multicolor)
        .animation(.smooth, value: fileStatus?.iCloudStatus)
    }
}
#endif

@available(macOS 26.0, iOS 26.0, *)
struct DrawOnAppearModifier: ViewModifier {
    
     var options: SymbolEffectOptions = .default
    
    @State private var isActive = false
    
    func body(content: Content) -> some View {
        content
            .symbolEffect(.drawOn, options: options, isActive: !isActive)
            .onAppear {
                withAnimation(.smooth) {
                    isActive = true
                }
            }
    }
}

extension View {
    @available(macOS 26.0, iOS 26.0, *)
    @ViewBuilder
    func drawOnAppear(options: SymbolEffectOptions = .default) -> some View {
        modifier(DrawOnAppearModifier(options: options))
    }
}



private struct PreviewView: View {
    @State private var isOn = false
    
    var body: some View {
        if #available(macOS 26.0, iOS 26.0, *) {
            VStack {
                ZStack {
                    if isOn {
                        Image(systemSymbol: .arrowTrianglehead2ClockwiseRotate90Icloud)
                            .drawOnAppear(options: .speed(2))
                    } else {
                        Image(systemSymbol: .checkmarkIcloud)
                            .drawOnAppear(options: .speed(2))
                    }
                }.border(.red)
                
                Button {
                    isOn.toggle()
                } label: {
                    Text("Toggle")
                }
            }
        }
    }
}

#Preview {
    PreviewView()
}
