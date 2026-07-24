//
//  FileHomeItemTransition.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 8/8/25.
//

import SwiftUI
import ChocofordUI
import CoreData
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

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

enum FileHomeCoverTransitionGeometry {
    static func rectIncludingIgnoredSafeArea(
        _ rect: CGRect,
        in geometry: GeometryProxy,
        includesBottom: Bool = true
    ) -> CGRect {
        let topInset = max(
            geometry.safeAreaInsets.top,
            geometry.frame(in: .global).minY
        )
        let bottomInset = includesBottom ? geometry.safeAreaInsets.bottom : 0
        let missingTopInset = min(
            topInset,
            max(0, topInset + rect.minY)
        )
        let missingBottomInset = min(
            bottomInset,
            max(0, geometry.size.height + bottomInset - rect.maxY)
        )

        guard missingTopInset > 0 || missingBottomInset > 0 else {
            return rect
        }
        return CGRect(
            x: rect.minX,
            y: rect.minY - missingTopInset,
            width: rect.width,
            height: rect.height + missingTopInset + missingBottomInset
        )
    }

    static func rectClosestToImageAspect(
        _ rect: CGRect,
        alternate candidate: CGRect,
        image: PlatformImage?
    ) -> CGRect {
        guard let imageAspect = image.map({ aspectRatio(pixelSize($0)) ?? 0 }),
              imageAspect > 0 else {
            return candidate
        }

        let rectDistance = abs((aspectRatio(rect.size) ?? 0) - imageAspect)
        let candidateDistance = abs((aspectRatio(candidate.size) ?? 0) - imageAspect)
        return candidateDistance < rectDistance ? candidate : rect
    }

    private static func pixelSize(_ image: PlatformImage) -> CGSize {
#if canImport(UIKit)
        if let cgImage = image.cgImage {
            return CGSize(
                width: CGFloat(cgImage.width),
                height: CGFloat(cgImage.height)
            )
        }
        return CGSize(
            width: image.size.width * image.scale,
            height: image.size.height * image.scale
        )
#elseif canImport(AppKit)
        var proposedRect = CGRect(origin: .zero, size: image.size)
        if let cgImage = image.cgImage(forProposedRect: &proposedRect, context: nil, hints: nil) {
            return CGSize(
                width: CGFloat(cgImage.width),
                height: CGFloat(cgImage.height)
            )
        }
        return image.size
#else
        return image.size
#endif
    }

    private static func aspectRatio(_ size: CGSize) -> Double? {
        guard size.width > 0, size.height > 0 else { return nil }
        return Double(size.width / size.height)
    }
}

struct FileHomeItemTransitionModifier: ViewModifier {
    private enum Phase {
        case idle
        case opening
        case dismissing
    }

    @Environment(\.managedObjectContext) private var viewContext
    @EnvironmentObject var fileState: FileState
    
    var openDuration: Double = 0.5
    var dismissDuration: Double = 0.3
    
    @State private var show: Bool = true
    @State private var animateFlag: Bool = false
    @State private var transitionRevision: Int = 0
    @State private var phase: Phase = .idle
    
    @State private var file: FileState.ActiveFile?
    
    @StateObject private var state = FileHomeItemTransitionState()
    @StateObject private var itemState = FileHomeItemTransitionItemState()
    
    func body(content: Content) -> some View {
        content
            .background {
                Color.clear
                    .anchorPreference(key: FileHomeItemPreferenceKey.self, value: .bounds) { value in
                        [FileHomeItemTransitionPreferenceID.destination: value]
                    }
            }
            .overlayPreferenceValue(FileHomeItemPreferenceKey.self) { value in
                let viewportDestinationAnchor = value[FileHomeItemTransitionPreferenceID.viewportDestination]
                let fallbackDestinationAnchor = value[FileHomeItemTransitionPreferenceID.destination]

                if let activeFile = file,// ?? fileState.currentActiveFile,
                   let sAnchor: Anchor<CGRect> = value[FileHomeItemTransitionPreferenceID.source(for: activeFile.id)],
                   let dAnchor: Anchor<CGRect> = viewportDestinationAnchor ?? fallbackDestinationAnchor {
                    GeometryReader { geomerty in
                        FileHomeItemHeroLayer(
                            file: activeFile,
                            show: show,
                            animateFlag: animateFlag,
                            sourceAnchor: sAnchor,
                            destinationAnchor: dAnchor,
                            usesExactViewportDestination: viewportDestinationAnchor != nil
                        )
                        .transition(.identity)
                        // .id(currentItem.id) // <-- important, cannot be `currentItem`
                    }
                }
            }
            .environmentObject(state)
            .environmentObject(itemState)
            .watch(value: fileState.currentActiveFile) { newValue in
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
                    beginOpenTransition(for: newValue, revision: revision)
                } else if oldValue != nil, newValue == nil {
                    // dismiss
                    phase = .dismissing
                    self.animateFlag = true
                    itemState.setSourceFileID(oldValue!.id)
                    itemState.setShouldHideItem(oldValue!.id)
                    state.canShowItemContainerView = true
                    self.show = true
                    
                    if #available(macOS 14.0, iOS 17.0, *) {
                        DispatchQueue.main.async {
                            guard revision == transitionRevision else { return }
                            withAnimation(
                                .smooth(duration: dismissDuration),
                                completionCriteria: .removed
                            ) {
                                self.animateFlag = false
                            } completion: {
                                guard revision == transitionRevision else { return }
                                completeDismissTransition()
                            }
                        }
                    } else {
                        DispatchQueue.main.async {
                            guard revision == transitionRevision else { return }
                            withAnimation(.smooth(duration: dismissDuration)) {
                                self.animateFlag = false
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + dismissDuration + 0.15) {
                                guard revision == transitionRevision else { return }
                                completeDismissTransition()
                            }
                        }
                    }
                } else if let newValue, phase != .idle {
                    // A new file was opened before the previous hero transition
                    // completed. Restart from the new item's source instead of
                    // leaving the interrupted dismiss state visible.
                    beginOpenTransition(for: newValue, revision: revision)
                } else {
                    self.file = newValue
                    itemState.setSourceFileID(nil)
                }
            }
    }

    private func beginOpenTransition(
        for file: FileState.ActiveFile,
        revision: Int
    ) {
        let animationDuration = fileState.consumeActiveFileOpenDurationOverride(for: file.id)
            ?? openDuration
        phase = .opening
        self.file = file
        itemState.setSourceFileID(file.id)
        itemState.setShouldHideItem(nil)
        state.canShowItemContainerView = true
        animateFlag = false
        show = true
        state.canShowExcalidrawCanvas = true

        if #available(macOS 14.0, iOS 17.0, *) {
            DispatchQueue.main.async {
                guard revision == transitionRevision else { return }
#if os(iOS)
                withAnimation(
                    .smooth(duration: animationDuration),
                    completionCriteria: .removed
                ) {
                    animateFlag = true
                } completion: {
                    guard revision == transitionRevision else { return }
                    completeOpenTransition()
                }
#else
                withAnimation(.smooth(duration: animationDuration)) {
                    animateFlag = true
                } completion: {
                    guard revision == transitionRevision else { return }
                    completeOpenTransition()
                }
#endif
            }
        } else {
            DispatchQueue.main.async {
                guard revision == transitionRevision else { return }
                withAnimation(.smooth(duration: animationDuration)) {
                    animateFlag = true
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + animationDuration + 0.15) {
                    guard revision == transitionRevision else { return }
                    completeOpenTransition()
                }
            }
        }
    }

    private func completeOpenTransition() {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            self.show = false
            state.canShowExcalidrawCanvas = true
            state.canShowItemContainerView = false
            itemState.setSourceFileID(nil)
            phase = .idle
        }
    }

    private func completeDismissTransition() {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            itemState.setShouldHideItem(nil)
            self.show = true
            self.file = nil
            itemState.setSourceFileID(nil)
            phase = .idle
        }
    }
    
    // private func onCurrentFileChanged
}

struct FileHomeItemHeroLayer: View {
    @Environment(\.colorScheme) var colorScheme

    @EnvironmentObject var appPreference: AppPreference
    @EnvironmentObject private var lockedContentState: LockedContentStateStore
    
    var file: FileState.ActiveFile
    var show: Bool
    var isAnimating: Bool
    var sourceAnchor: Anchor<CGRect>
    var destinationAnchor: Anchor<CGRect>
    var usesExactViewportDestination: Bool

    init(
        file: FileState.ActiveFile,
        show: Bool,
        animateFlag: Bool,
        sourceAnchor: Anchor<CGRect>,
        destinationAnchor: Anchor<CGRect>,
        usesExactViewportDestination: Bool
    ) {
        self.file = file
        self.show = show
        self.isAnimating = animateFlag
        self.sourceAnchor = sourceAnchor
        self.destinationAnchor = destinationAnchor
        self.usesExactViewportDestination = usesExactViewportDestination
    }
    
    var cacheKey: String {
        colorScheme == .light ? file.id + "_light" : file.id + "_dark"
    }

    var lockState: FileContentLockState? {
        lockedContentState.previewLockState(for: file)
    }
    
    var platformImage: PlatformImage? {
        guard let lockState,
              lockState != .locked else { return nil }
        return FileItemPreviewCache.shared.object(forKey: cacheKey as NSString)
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
            let adjustedDRect = adjustedDestinationRect(
                dRect,
                in: geomerty
            )
            
            FileHomeItemHeroSurface(
                show: show,
                progress: isAnimating ? 1 : 0,
                sourceRect: sRect,
                destinationRect: adjustedDRect,
                lockState: lockState,
                platformImage: platformImage,
                background: background
            )
        }
    }

    private func adjustedDestinationRect(
        _ rect: CGRect,
        in geometry: GeometryProxy
    ) -> CGRect {
        if usesExactViewportDestination {
            return viewportAdjustedDestinationRect(rect, in: geometry)
        }

        return platformAdjustedDestinationRect(rect, in: geometry)
    }

    private func viewportAdjustedDestinationRect(
        _ rect: CGRect,
        in geometry: GeometryProxy
    ) -> CGRect {
#if os(iOS)
        return FileHomeCoverTransitionGeometry.rectClosestToImageAspect(
            rect,
            alternate: FileHomeCoverTransitionGeometry.rectIncludingIgnoredSafeArea(
                rect,
                in: geometry
            ),
            image: platformImage
        )
#else
        return rect
#endif
    }

    private func platformAdjustedDestinationRect(
        _ rect: CGRect,
        in geometry: GeometryProxy
    ) -> CGRect {
#if os(macOS)
        let topInset = max(
            geometry.safeAreaInsets.top,
            geometry.frame(in: .global).minY
        )
        guard topInset > 0 else { return rect }
        return CGRect(
            x: rect.minX,
            y: rect.minY - topInset,
            width: rect.width,
            height: rect.height + topInset
        )
#elseif os(iOS)
        return FileHomeCoverTransitionGeometry.rectClosestToImageAspect(
            rect,
            alternate: FileHomeCoverTransitionGeometry.rectIncludingIgnoredSafeArea(
                rect,
                in: geometry
            ),
            image: platformImage
        )
#else
        return rect
#endif
    }

}

private struct FileHomeItemHeroSurface: View, Animatable {
    var show: Bool
    var progress: CGFloat
    var sourceRect: CGRect
    var destinationRect: CGRect
    var lockState: FileContentLockState?
    var platformImage: PlatformImage?
    var background: Color

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    var body: some View {
        ZStack {
            if lockState == .locked {
                LockedFilePreviewPlaceholder(
                    showsIcon: true,
                    iconSize: lockIconSize
                )
            } else if lockState == nil {
                LockedFilePreviewPlaceholder()
            } else {
                background

                if let platformImage {
                    Image(platformImage: platformImage)
                        .resizable()
                        .scaledToFill()
                }
            }
        }
        .frame(width: currentRect.width, height: currentRect.height)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        .background {
            if show {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(background)
                    .shadow(
                        color: Color.gray.opacity(shadowOpacity),
                        radius: shadowRadius
                    )
            }
        }
        .offset(x: currentRect.minX, y: currentRect.minY)
        .transition(.identity)
        // can not use with if condition
        .opacity(show ? 1 : 0) // <-- important
        // .animation(.default, value: show)
    }

    private var currentRect: CGRect {
        CGRect(
            x: interpolate(sourceRect.minX, destinationRect.minX),
            y: interpolate(sourceRect.minY, destinationRect.minY),
            width: interpolate(sourceRect.width, destinationRect.width),
            height: interpolate(sourceRect.height, destinationRect.height)
        )
    }

    private var cornerRadius: CGFloat {
        12 * (1 - progress)
    }

    private var shadowRadius: CGFloat {
        8 * transitionLift
    }

    private var shadowOpacity: CGFloat {
        0.18 * transitionLift
    }

    private var transitionLift: CGFloat {
        max(0, 1 - abs(progress * 2 - 1))
    }

    private var lockIconSize: CGFloat {
        let sourceIconSize: CGFloat = sourceRect.height <= 70 ? 22 : 34
        let destinationIconSize: CGFloat = 72
        return interpolate(sourceIconSize, destinationIconSize)
    }

    private func interpolate(_ source: CGFloat, _ destination: CGFloat) -> CGFloat {
        source + (destination - source) * progress
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
