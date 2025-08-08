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
        fileState.currentActiveFile = .file(file)
        fileState.currentActiveGroup = file.group != nil ? .group(file.group!) : nil
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
