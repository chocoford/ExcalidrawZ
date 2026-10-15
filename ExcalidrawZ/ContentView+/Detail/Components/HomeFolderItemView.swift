//
//  HomeFolderItemView.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 8/3/25.
//

import SwiftUI
import ChocofordUI

struct HomeFolderItemView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.fileHomeItemHoverEffectsEnabled) private var hoverEffectsEnabled
    @Environment(\.fileHomeItemHoverAnimationsEnabled) private var hoverAnimationsEnabled
    @Environment(\.fileHomeItemHoverSuppressed) private var hoverSuppressed
    var isSelected: Bool
    var isHighlighted: Bool
    var name: String
    var itemsCount: Int
    var isLoading = false
    var localFolder: LocalFolder?
    
    @State private var isHovered = false
    @State private var pointerHoverState = FileHomeItemPointerHoverState()
    private var showsHoverShadow: Bool { hoverEffectsEnabled && !hoverSuppressed && isHovered }
    
    var body: some View {
        HStack(spacing: 10) {
            Image(systemSymbol: .folderFill)
                .resizable()
                .scaledToFit()
                .frame(height: 24)
                .foregroundStyle(Color(red: 12/255.0, green: 157/255.0, blue: 229/255.0))
            
            VStack(alignment: .leading) {
                Text(name)
                    .font(.headline)
                    .lineLimit(1)
                if #available(macOS 13.0, iOS 16.0, *) {
                    Text(localizable: .homeGroupItemsFormatter(itemsCount))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                   
                }
            }
                   
            Spacer()
            if let localFolder {
                LocalFolderAvailabilityIndicator(folder: localFolder)
            }
            if isLoading {
                ProgressView()
                    .controlSize(.mini)
                    .frame(width: 12, height: 12)
            }
            if #available(macOS 13.0, iOS 16.0, *) {} else {
                Text(itemsCount.formatted())
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .apply { view in
            if hoverEffectsEnabled {
                view.onHover { hovered in
                    pointerHoverState.isInside = hovered
                    guard !hoverSuppressed else { return }
                    updateHovered(hovered)
                }
            } else {
                view
            }
        }
        .background {
            ZStack {
                if #available(macOS 26.0, iOS 26.0, *) {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(
                            isHighlighted
                            ? AnyShapeStyle(Color.accentColor)
                            : colorScheme == .light
                            ? AnyShapeStyle(HierarchicalShapeStyle.secondary)
                            : AnyShapeStyle(Color.clear)
                        )
                        .stroke(
                            isSelected
                            ? AnyShapeStyle(Color.accentColor)
                            : AnyShapeStyle(SeparatorShapeStyle())
                        )
                        .glassEffect(.clear, in: .rect(cornerRadius: 12))
                        .shadow(
                            color: colorScheme == .light
                                ? Color.gray.opacity(0.33)
                                : Color.black.opacity(0.33),
                            radius: showsHoverShadow ? (colorScheme == .light ? 2 : 6) : 0
                        )
                    
                } else {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(
                            isHighlighted
                            ? AnyShapeStyle(Color.accentColor)
                            : AnyShapeStyle(BackgroundStyle())
                        )
                        .shadow(
                            color: colorScheme == .light
                                ? Color.gray.opacity(0.2)
                                : Color.black.opacity(0.2),
                            radius: showsHoverShadow ? 4 : 0
                        )
                    
                    let nonSelectedStrokeStyle = if #available(macOS 12.0, iOS 17.0, *) {
                        AnyShapeStyle(SeparatorShapeStyle())
                    } else {
                        AnyShapeStyle(HierarchicalShapeStyle.secondary)
                    }
                    
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(
                            isSelected
                            ? AnyShapeStyle(Color.accentColor)
                            : nonSelectedStrokeStyle
                        )
                }
            }
            .animation(
                hoverAnimationsEnabled ? .smooth(duration: 0.2) : nil,
                value: showsHoverShadow
            )
        }
        .watch(value: hoverSuppressed) { _, suppressed in
            updateHovered(!suppressed && pointerHoverState.isInside)
        }
        .onDisappear {
            pointerHoverState.isInside = false
            updateHovered(false, animated: false)
        }
    }

    private func updateHovered(_ hovered: Bool, animated: Bool = true) {
        guard isHovered != hovered else { return }
        var transaction = Transaction()
        transaction.disablesAnimations = !animated || hoverSuppressed || !hoverAnimationsEnabled
        withTransaction(transaction) {
            isHovered = hovered
        }
    }
}


struct HomeFolderItemDropModifier<HomeGroup: ExcalidrawGroup>: ViewModifier {
    var group: HomeGroup
    
    func body(content: Content) -> some View {
        if let group = group as? Group {
            content
                .modifier(
                    GroupRowDropModifier(group: group) { item in
                            .below(item)
                    }
                )
        } else if let folder = group as? LocalFolder {
            content
                .modifier(LocalFolderDropModifier(
                    folder: folder,
                    dropTarget: { item in
                            .below(item)
                    }
                ))
        }
        
    }
}
