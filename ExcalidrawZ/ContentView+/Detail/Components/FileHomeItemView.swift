//
//  FileHomeItemView.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 8/3/25.
//

import SwiftUI
import ChocofordUI

struct FileHomeItemView: View {
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.managedObjectContext) var viewContext
    @EnvironmentObject var fileState: FileState

    @Binding var isSelected: Bool
    var file: File
    
    @State private var coverImage: Image? = nil
    
    @State private var width: CGFloat?
    
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
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(isSelected ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(SeparatorShapeStyle()))
        }
        .background {
            RoundedRectangle(cornerRadius: 12)
                .fill(.background)
                .shadow(color: Color.gray.opacity(0.2), radius: 4)
        }
        .overlay {
            Color.clear
                .contentShape(Rectangle())
                .simultaneousGesture(TapGesture(count: 2).onEnded {
                    fileState.currentFile = file
                    if let groupID = file.group?.objectID {
                        fileState.expandToGroup(groupID)
                    }
                })
                .simultaneousGesture(TapGesture().onEnded {
                    isSelected = true
                })
                .contextMenu {
                    contextMenu()
                }
        }
        .watchImmediately(of: file) { newValue in
            if let excalidrawFile = try? ExcalidrawFile(from: newValue.objectID, context: viewContext) {
                Task {
                    while fileState.excalidrawWebCoordinator?.isLoading == true {
                        try? await Task.sleep(nanoseconds: UInt64(1e+9 * 1))
                    }
                    
                    if let image = try? await fileState.excalidrawWebCoordinator?.exportElementsToPNG(
                        elements: excalidrawFile.elements,
                        colorScheme: colorScheme
                    ) {
                        Task.detached {
                            let image = Image(platformImage: image)
                            await MainActor.run {
                                self.coverImage = image
                            }
                        }
                    }
                }
            }
        }
    }
    
    @MainActor @ViewBuilder
    private func contextMenu() -> some View {
        Button {
            fileState.currentFile = file
        } label: {
            Label("Open", systemSymbol: .arrowRightCircle)
        }
        
        Divider()
        
        Button {
            
        } label: {
            Label(.localizable(.generalButtonDelete), systemSymbol: .trash)
        }
    }
}
