//
//  LayoutState.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 2024/11/18.
//

import SwiftUI

final class LayoutState: ObservableObject {
    @Published var isSidebarPresented: Bool = true
    @Published var isInspectorPresented: Bool = false
    
    @Published var isResotreAlertIsPresented: Bool = false
}
