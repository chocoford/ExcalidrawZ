//
//  FileHomeItemView.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 8/3/25.
//

import SwiftUI
import ChocofordUI

struct FileHomeItemPreferenceKey: PreferenceKey {
    static var defaultValue: [String: Anchor<CGRect>] = [:]
    
    static func reduce(value: inout [String: Anchor<CGRect>], nextValue: () ->  [String: Anchor<CGRect>]) {
        value.merge(nextValue()) { $1 }
    }
}

class FileItemPreviewCache: NSCache<NSManagedObjectID, NSImage> {
    static let shared = FileItemPreviewCache()
}

struct FileHomeItemView: View {
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.managedObjectContext) var viewContext
    @EnvironmentObject var fileState: FileState
    @EnvironmentObject private var fileHomeItemTransitionState: FileHomeItemTransitionState

    @Binding var isSelected: Bool
    var file: File
    
    @State private var coverImage: Image? = nil
    
    @State private var width: CGFloat?
    
    static let roundedCornerRadius: CGFloat = 12
    
    let cache = FileItemPreviewCache.shared
    
    var body: some View {
        VStack(spacing: 0) {
            if let coverImage {
                Color.clear
                    .overlay {
                        coverImage
                            .resizable()
                            .scaledToFill()
                            .allowsHitTesting(false)
                    }
                    .clipShape(Rectangle())
                    .frame(height: width == nil ? 180 : width! * 0.5625)
            } else {
                Color.clear
                    .overlay {
                        ProgressView()
                            .controlSize(.small)
                            .padding(.bottom, 40)
                    }
                    .frame(height: width == nil ? 180 : width! * 0.5625)
            }
        }
        .readWidth($width)
        .overlay(alignment: .bottom) {
            HStack {
                Text(file.name ?? String(localizable: .generalUntitled))
                    .lineLimit(1)
                    .font(.headline)
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(.regularMaterial)
        }
        .clipShape(RoundedRectangle(cornerRadius: Self.roundedCornerRadius))
        .overlay {
            RoundedRectangle(cornerRadius: Self.roundedCornerRadius)
                .stroke(isSelected ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(SeparatorShapeStyle()))
        }
        .background {
            RoundedRectangle(cornerRadius: Self.roundedCornerRadius)
                .fill(.background)
                .shadow(color: Color.gray.opacity(0.2), radius: 4)
        }
        .background {
            Color.clear
                .anchorPreference(key: FileHomeItemPreferenceKey.self, value: .bounds) { value in
                    [file.objectID.description+"SOURCE": value]
                }
        }
        .overlay {
            Color.clear
                .contentShape(Rectangle())
                .simultaneousGesture(TapGesture(count: 2).onEnded {
                    openFile(file)
                })
                .simultaneousGesture(TapGesture().onEnded {
                    isSelected = true
                })
                .modifier(FileContextMenuModifier(file: file))
        }
        .opacity(fileHomeItemTransitionState.shouldHideItem == file.objectID ? 0 : 1)
        .onChange(of: file) { newValue in
            self.getElementsImage(fileID: newValue.objectID)
        }
        .onAppear {
            if let image = cache.object(forKey: file.objectID) {
                Task.detached {
                    let image = Image(platformImage: image)
                    await MainActor.run {
                        self.coverImage = image
                    }
                }
            } else {
                self.getElementsImage(fileID: file.objectID)
            }
        }
    }
    
    private func getElementsImage(fileID: NSManagedObjectID) {
        if let excalidrawFile = try? ExcalidrawFile(from: fileID, context: viewContext) {
            Task {
                while fileState.excalidrawWebCoordinator?.isLoading == true {
                    try? await Task.sleep(nanoseconds: UInt64(1e+9 * 1))
                }
                
                if let image = try? await fileState.excalidrawWebCoordinator?.exportElementsToPNG(
                    elements: excalidrawFile.elements,
                    colorScheme: colorScheme
                ) {
                    Task.detached {
                        await MainActor.run {
                            cache.setObject(image, forKey: fileID)
                        }
                        let image = Image(platformImage: image)
                        await MainActor.run {
                            self.coverImage = image
                        }
                    }
                }
            }
        }
    }
    
    private func openFile(_ file: File) {
        fileState.currentFile = file
        fileState.currentGroup = file.group
        if let groupID = file.group?.objectID {
            fileState.expandToGroup(groupID)
        }
    }
    
    @ViewBuilder
    static func placeholder() -> some View {
        ViewSizeReader { size in
            let width = size.width > 0 ? size.width : nil
            if #available(macOS 14.0, *) {
                RoundedRectangle(cornerRadius: roundedCornerRadius)
                    .fill(.placeholder)
                    .opacity(0.2)
                    .frame(height: width == nil ? 180 : width! * 0.5625)
            } else {
                RoundedRectangle(cornerRadius: roundedCornerRadius)
                    .fill(Color.gray.opacity(0.1))
                    .frame(height: width == nil ? 180 : width! * 0.5625)
            }
        }
    }
}

final class FileHomeItemTransitionState: ObservableObject {
    
    @Published var shouldHideItem: NSManagedObjectID? = nil
    
    
    
    @Published var canShowExcalidrawCanvas: Bool = false
    @Published var canShowItemContainerView: Bool = true
    
    func toggleOpenTransition() {
        
    }
    
    func toggleCloseTransition() {
        
    }
}

struct FileHomeItemTransitionModifier: ViewModifier {
    @EnvironmentObject var fileState: FileState
    
    var duration: Double = 1
    
    @State private var show: Bool = true
    @State private var animateFlag: Bool = false
    
    @State private var file: File?
    
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
                if let activeFile = file ?? fileState.currentFile,
                   let sAnchor: Anchor<CGRect> = value[activeFile.objectID.description + "SOURCE"],
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
            .onChange(of: fileState.currentFile) { newValue in
                let oldValue = self.file

                if oldValue == nil, let newValue { // open
                    state.canShowItemContainerView = true
                    self.animateFlag = false
                    self.show = true
                    state.canShowExcalidrawCanvas = false
                    
                    withAnimation(.smooth(duration: duration)) {
                        self.animateFlag = true
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + duration + 0.1) {
                        withAnimation {
                            self.show = false
                            state.canShowExcalidrawCanvas = true
                        }
                        self.file = newValue
                        state.canShowItemContainerView = false
                    }
                } else if oldValue != nil, newValue == nil {
                    // dismiss
                    
                    self.animateFlag = true
                    state.shouldHideItem = oldValue!.objectID
                    state.canShowItemContainerView = true
                    self.show = true
                    
                    withAnimation(.bouncy(duration: duration / 2)) {
                        self.animateFlag = false
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + duration / 2 + 0.1) {
                        self.show = true
                        self.file = nil
                        state.shouldHideItem = nil
                        
                    }
                }
            }
            .onChange(of: file) { newValue in
                
            }
    }
    
    // private func onCurrentFileChanged
}

struct FileHomeItemHeroLayer: View {
    @Environment(\.colorScheme) var colorScheme
    
    @EnvironmentObject var appPreference: AppPreference
    
    var file: File
    var show: Bool
    var isAnimating: Bool
    var sourceAnchor: Anchor<CGRect>
    var destinationAnchor: Anchor<CGRect>

    init(
        file: File,
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
        FileItemPreviewCache.shared.object(forKey: file.objectID)
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
