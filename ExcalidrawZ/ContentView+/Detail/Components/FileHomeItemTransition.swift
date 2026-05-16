//
//  FileHomeItemTransition.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 8/8/25.
//

import SwiftUI
import CoreData

final class FileHomeItemTransitionState: ObservableObject {
    @Published var canShowExcalidrawCanvas: Bool = false
    @Published var canShowItemContainerView: Bool = true
}

final class FileHomeItemTransitionItemState: ObservableObject {
    @Published private(set) var shouldHideItem: String?
    @Published private(set) var sourceFileID: String?

    func setShouldHideItem(_ value: String?) {
        guard shouldHideItem != value else { return }
        shouldHideItem = value
    }

    func setSourceFileID(_ value: String?) {
        guard sourceFileID != value else { return }
        sourceFileID = value
    }
}

struct FileHomeItemTransitionModifier: ViewModifier {
    @Environment(\.managedObjectContext) private var viewContext
    @EnvironmentObject var fileState: FileState
    
    var duration: Double = 0.5
    
    @State private var show: Bool = true
    @State private var animateFlag: Bool = false
    @State private var transitionRevision: Int = 0
    
    @State private var file: FileState.ActiveFile?
    
    @StateObject private var state = FileHomeItemTransitionState()
    @StateObject private var itemState = FileHomeItemTransitionItemState()
    
    func body(content: Content) -> some View {
        content
            .background {
                Color.clear
                    .anchorPreference(key: FileHomeItemPreferenceKey.self, value: .bounds) { value in
                        ["DEST": value]
                    }
            }
            .overlayPreferenceValue(FileHomeItemPreferenceKey.self) { value in
                if let activeFile = file,// ?? fileState.currentActiveFile,
                   let sAnchor: Anchor<CGRect> = value[activeFile.id + "SOURCE"],
                   let dAnchor: Anchor<CGRect> = value["DEST"] {
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
            .environmentObject(itemState)
            .onChange(of: fileState.currentActiveFile) { newValue in
                let oldValue = self.file
                transitionRevision += 1
                let revision = transitionRevision
   
                /// Check if the newValue is in the same group as currentActiveGroup
                func groupCheck(file: FileState.ActiveFile?) -> Bool {
                    switch file {
                        case .file(let file):
                            guard case .group(let group) = fileState.currentActiveGroup,
                               file.group == group else {
                                return false
                            }
                        case .collaborationFile:
                            guard fileState.isInCollaborationSpace else {
                                return false
                            }
                        case .localFile(let url):
                            let fetchRequest = NSFetchRequest<LocalFolder>(entityName: "LocalFolder")
                            fetchRequest.predicate = NSPredicate(format: "url == %@", url.deletingLastPathComponent() as CVarArg)
                            fetchRequest.fetchLimit = 1
                            guard let folder = ((try? viewContext.fetch(fetchRequest)) ?? []).first,
                                  case .localFolder(let f) = fileState.currentActiveGroup,
                                  folder == f else {
                                return false
                            }
                        default:
                            break
                    }
                    return true
                }
                
//                if !groupCheck(file: newValue) {
//                    withOpenFileDelay {
//                        self.file = newValue
//                        state.canShowExcalidrawCanvas = true
//                        state.canShowItemContainerView = false
//                    }
//                    return
//                }
                
//                if !groupCheck(file: oldValue) {
//                    self.file = nil
//                    state.canShowExcalidrawCanvas = false
//                    state.canShowItemContainerView = true
//                }
                
                if oldValue == nil, let newValue { // open
                    self.file = newValue
                    itemState.setSourceFileID(newValue.id)
                    itemState.setShouldHideItem(nil)
                    state.canShowItemContainerView = true
                    self.animateFlag = false
                    self.show = true
                    state.canShowExcalidrawCanvas = false
                    
                    if #available(macOS 14.0, iOS 17.0, *) {
                        DispatchQueue.main.async {
                            guard revision == transitionRevision else { return }
                            withAnimation(.smooth(duration: duration)) {
                                self.animateFlag = true
                            } completion: {
                                guard revision == transitionRevision else { return }
                                withAnimation {
                                    self.show = false
                                    state.canShowExcalidrawCanvas = true
                                }

                                state.canShowItemContainerView = false
                                itemState.setSourceFileID(nil)
                            }
                        }
                    } else {
                        DispatchQueue.main.async {
                            guard revision == transitionRevision else { return }
                            withAnimation(.smooth(duration: duration)) {
                                self.animateFlag = true
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + duration + 0.15) {
                                guard revision == transitionRevision else { return }
                                withAnimation {
                                    self.show = false
                                    state.canShowExcalidrawCanvas = true
                                }
                                // self.file = newValue
                                state.canShowItemContainerView = false
                                itemState.setSourceFileID(nil)
                            }
                        }
                    }
                } else if oldValue != nil, newValue == nil {
                    // dismiss
                    
                    self.animateFlag = true
                    itemState.setSourceFileID(oldValue!.id)
                    itemState.setShouldHideItem(oldValue!.id)
                    state.canShowItemContainerView = true
                    self.show = true
                    
                    if #available(macOS 14.0, iOS 17.0, *) {
                        DispatchQueue.main.async {
                            guard revision == transitionRevision else { return }
                            withAnimation(.smooth(duration: duration)) {
                                self.animateFlag = false
                            } completion: {
                                guard revision == transitionRevision else { return }
                                self.show = true
                                self.file = nil
                                itemState.setSourceFileID(nil)
                                itemState.setShouldHideItem(nil)
                            }
                        }
                    } else {
                        DispatchQueue.main.async {
                            guard revision == transitionRevision else { return }
                            withAnimation(.smooth(duration: duration)) {
                                self.animateFlag = false
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + duration + 0.15) {
                                guard revision == transitionRevision else { return }
                                self.show = true
                                self.file = nil
                                itemState.setSourceFileID(nil)
                                itemState.setShouldHideItem(nil)
                            }
                        }
                    }
                } else {
                    self.file = newValue
                    itemState.setSourceFileID(nil)
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
    
    var cacheKey: String {
        colorScheme == .light ? file.id + "_light" : file.id + "_dark"
    }
    
    var platformImage: PlatformImage? {
        FileItemPreviewCache.shared.object(forKey: cacheKey as NSString)
    }

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

                if let platformImage {
                    Image(platformImage: platformImage)
                        .resizable()
                        .scaledToFill()
                }
            }
            .frame(width: viewSize.width, height: viewSize.height)
            .clipShape(RoundedRectangle(cornerRadius: isAnimating ? 0 : 12))
            .background {
                if show {
                    RoundedRectangle(cornerRadius: isAnimating ? 0 : 12)
                        .fill(background)
                        .shadow(
                            color: isAnimating ? .clear : Color.gray.opacity(0.2),
                            radius: isAnimating ? 0 : 4
                        )
                }
            }
            .offset(viewPosition)
            .transition(.identity)
            // can not use with if condition
            .opacity(show ? 1 : 0) // <-- important
            // .animation(.default, value: show)
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
