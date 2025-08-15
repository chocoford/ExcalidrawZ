//
//  FileHomeItemTransition.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 8/8/25.
//

import SwiftUI

final class FileHomeItemTransitionState: ObservableObject {
    
    @Published var shouldHideItem: String? = nil
    
    
    
    @Published var canShowExcalidrawCanvas: Bool = false
    @Published var canShowItemContainerView: Bool = true
    
    func toggleOpenTransition() {
        
    }
    
    func toggleCloseTransition() {
        
    }
}

struct FileHomeItemTransitionModifier: ViewModifier {
    @EnvironmentObject var fileState: FileState
    
    var duration: Double = 0.5
    
    @State private var show: Bool = true
    @State private var animateFlag: Bool = false
    
    @State private var file: FileState.ActiveFile?
    
    @State private var state: FileHomeItemTransitionState = FileHomeItemTransitionState()
    
    func body(content: Content) -> some View {
        content
            .background {
                Color.clear
                    .anchorPreference(key: FileHomeItemPreferenceKey.self, value: .bounds) { value in
                        ["DEST": value]
                    }
            }
            .overlayPreferenceValue(FileHomeItemPreferenceKey.self) { value in
                
                
                if let activeFile = file ?? fileState.currentActiveFile,
                   let sAnchor: Anchor<CGRect> = value[activeFile.id + "SOURCE"],
                   let dAnchor: Anchor<CGRect> = value["DEST"] {
                    // let _ = print("FileHomeItemTransitionModifier: \(activeFile.objectID.description)")
                    GeometryReader { geomerty in
                        FileHomeItemHeroLayer(
                            file: activeFile,
                            show: show,
                            animateFlag: animateFlag,
                            sourceAnchor: sAnchor,
                            destinationAnchor: dAnchor
                        )
                        .transition(.opacity.animation(.smooth(duration: 0.3)))
                        // .id(currentItem.id) // <-- important, cannot be `currentItem`
                    }
                }
            }
            .environmentObject(state)
            .onChange(of: fileState.currentActiveFile) { newValue in
                let oldValue = self.file

                if oldValue == nil, let newValue { // open
                    state.canShowItemContainerView = true
                    self.animateFlag = false
                    self.show = true
                    state.canShowExcalidrawCanvas = false
                    
                    if #available(macOS 14.0, iOS 17.0, *) {
                        withAnimation(.smooth(duration: duration)) {
                            self.animateFlag = true
                        } completion: {
                            withAnimation {
                                self.show = false
                                state.canShowExcalidrawCanvas = true
                            }
                            self.file = newValue
                            state.canShowItemContainerView = false
                        }
                    } else {
                        withAnimation(.smooth(duration: duration)) {
                            self.animateFlag = true
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + duration + 0.15) {
                            withAnimation {
                                self.show = false
                                state.canShowExcalidrawCanvas = true
                            }
                            self.file = newValue
                            state.canShowItemContainerView = false
                        }
                    }
                } else if oldValue != nil, newValue == nil {
                    // dismiss
                    
                    self.animateFlag = true
                    state.shouldHideItem = oldValue!.id
                    state.canShowItemContainerView = true
                    self.show = true
                    
                    if #available(macOS 14.0, iOS 17.0, *) {
                        withAnimation(.smooth(duration: duration)) {
                            self.animateFlag = false
                        } completion: {
                            self.show = true
                            self.file = nil
                            state.shouldHideItem = nil
                        }
                    } else {
                        withAnimation(.smooth(duration: duration)) {
                            self.animateFlag = false
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + duration + 0.15) {
                            self.show = true
                            self.file = nil
                            state.shouldHideItem = nil
                        }
                    }
                }
            }
    }
    
    // private func onCurrentFileChanged
}

struct FileHomeItemHeroLayer: View {
    @Environment(\.colorScheme) var colorScheme
    
    @EnvironmentObject var appPreference: AppPreference
    
    var file: FileState.ActiveFile
    var show: Bool
    var isAnimating: Bool
    var sourceAnchor: Anchor<CGRect>
    var destinationAnchor: Anchor<CGRect>

    init(
        file: FileState.ActiveFile,
        show: Bool,
        animateFlag: Bool,
        sourceAnchor: Anchor<CGRect>,
        destinationAnchor: Anchor<CGRect>
    ) {
        self.file = file
        self.show = show
        self.isAnimating = animateFlag
        self.sourceAnchor = sourceAnchor
        self.destinationAnchor = destinationAnchor
    }
    
    var platformImage: NSImage? {
        FileItemPreviewCache.shared.object(forKey: file.id as NSString)
    }
    
    @State private var image: Image?
    
    var background: Color {
        appPreference.excalidrawAppearance.colorScheme
        ?? appPreference.appearance.colorScheme
        ?? colorScheme == .dark
        ? Color.black
        : Color.white
    }
    
    var body: some View {
        GeometryReader { geomerty in
            let sRect = geomerty[sourceAnchor]
            let dRect = geomerty[destinationAnchor]
            
            let viewSize: CGSize = CGSize(
                width: isAnimating ? dRect.width : sRect.width,
                height: isAnimating ? dRect.height : sRect.height
            )
            let viewPosition: CGSize = CGSize(
                width: isAnimating ? dRect.minX : sRect.minX,
                height: isAnimating ? dRect.minY : sRect.minY
            )
            
            ZStack {
                background

                image?
                    .resizable()
                    .scaledToFill()
            }
            .drawingGroup()
            .frame(width: viewSize.width, height: viewSize.height)
            .clipShape(RoundedRectangle(cornerRadius: isAnimating ? 0 : 12))
            .background {
                if show {
                    RoundedRectangle(cornerRadius: isAnimating ? 0 : 12)
                        .fill(background)
                        .shadow(color: Color.gray.opacity(0.2), radius: 4)
                }
            }
            .offset(viewPosition)
            .transition(.identity)
            // can not use with if condition
            .opacity(show ? 1 : 0) // <-- important
            // .animation(.default, value: show)
        }
        .onAppear {
            guard let platformImage else { return }
            Task.detached {
                let image = Image(platformImage: platformImage)
                await MainActor.run {
                    self.image = image
                }
            }
        }
    }
}

struct SizeAnimatableContainer: Animatable, View {
    var content: AnyView
    var viewSize: CGSize
    
    init<Content: View>(
        viewSize: CGSize,
        @ViewBuilder content: () -> Content,
    ) {
        self.content = AnyView(content())
        self.viewSize = viewSize
    }
    
    var animatableData: CGSize {
        get { viewSize }
        set { viewSize = newValue }
    }
    
    var body: some View {
        content
        .frame(width: animatableData.width, height: animatableData.height)
    }
}

