//
//  TreeStructureView.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 3/3/25.
//

import SwiftUI

import ChocofordUI

private struct TreeStructureDepthKey: EnvironmentKey {
    static let defaultValue: Int = 0
}

extension EnvironmentValues {
    fileprivate var treeStructureDepth: Int {
        get { self[TreeStructureDepthKey.self] }
        set { self[TreeStructureDepthKey.self] = newValue }
    }
}


private struct TreeStructureIsLastKey: EnvironmentKey {
    static let defaultValue: Bool = true
}

extension EnvironmentValues {
    fileprivate var treeStructureIsLast: Bool {
        get { self[TreeStructureIsLastKey.self] }
        set { self[TreeStructureIsLastKey.self] = newValue }
    }
}


struct TreeStructureView<Children: RandomAccessCollection, ChildView: View, ID: Hashable>: View
where Children.Element : Hashable {
    @Environment(\.treeStructureDepth) var depth
    @Environment(\.treeStructureIsLast) var isLast
    
    var root: AnyView
    var paddingLeading: CGFloat
    var children: Children
    var childrenID: KeyPath<Children.Element, ID>
    var childView: (Children.Element) -> ChildView
    
    init<Root: View>(
        children: Children,
        paddingLeading: CGFloat = 0,
        @ViewBuilder root: () -> Root,
        @ViewBuilder childView: @escaping (Children.Element) -> ChildView
    ) where Children.Element : Identifiable, ID == Children.Element.ID {
        self.children = children
        self.childrenID = \.id
        self.paddingLeading = paddingLeading
        self.root = AnyView(root())
        self.childView = childView
    }
    
    
    init<Root: View>(
        children: Children,
        id: KeyPath<Children.Element, ID>,
        paddingLeading: CGFloat = 0,
        @ViewBuilder root: () -> Root,
        @ViewBuilder childView: @escaping (Children.Element) -> ChildView
    ) {
        self.children = children
        self.childrenID = id
        self.paddingLeading = paddingLeading
        self.root = AnyView(root())
        self.childView = childView
    }
    
    
    
    var paddingBase: CGFloat { 14 }
    @State private var height: CGFloat = .zero
    
    var body: some View {
        let fillStyle = if #available(iOS 17.0, *) {
            AnyShapeStyle(.separator)
        } else {
            AnyShapeStyle(.secondary)
        }
        VStack(alignment: .leading, spacing: 0) {
            root
                .readHeight($height)
            
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(children, id: childrenID) { child in
                    let isLast = child == children.last

                    childView(child)
                        .environment(\.treeStructureDepth, depth+1)
                        .environment(\.treeStructureIsLast, isLast)
                        .padding(.leading, paddingBase)
                        .overlay(alignment: .topLeading) {
                            HStack(spacing: 0) {
                                VStack(spacing: 0) {
                                    Rectangle()
                                        .fill(fillStyle)
                                        .frame(width: 1, height: height / 2)
                                    
                                    Rectangle()
                                        .fill(fillStyle)
                                        .frame(width: 1, height: height / 2)
                                        .opacity(isLast ? 0 : 1)
                                }
                                
                                Rectangle()
                                    .fill(fillStyle)
                                    .frame(width: 5, height: 1)
                            }
                            .padding(.leading, 6 + paddingLeading)
                        }
                }
            }
            .overlay(alignment: .leading) {
                if !isLast {
                    Rectangle()
                        .fill(fillStyle)
                        .frame(width: 1)
                        .offset(x: -8 + paddingLeading)
                }
            }
        }
    }
}

private struct TreeStructureChild: Hashable, Identifiable {
    var id = UUID()
    var children: [TreeStructureChild] = []
}

#Preview {
    
    let children = [TreeStructureChild(children: [TreeStructureChild(), TreeStructureChild()])]
    TreeStructureView(children: children, paddingLeading: 10) {
        HStack {
            Image(systemSymbol: .folder).font(.footnote)
            Text("Folder")
        }
    } childView: { child in
        TreeStructureView(children: child.children, paddingLeading: 10) {
            HStack {
                Image(systemSymbol: .folder).font(.footnote)
                Text("SubFolder")
            }
        } childView: { child in
            Text("node")
        }

    }
    .padding(40)

}
