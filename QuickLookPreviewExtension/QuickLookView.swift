//
//  QuickLookView.swift
//  QuickLookPreviewExtension
//
//  Created by Dove Zachary on 2024/10/8.
//

import SwiftUI
import WebKit
import Combine

import SwiftyAlert

struct QuickLookView: View {
    @Environment(\.alertToast) var alertToast

    @ObservedObject var state: PreviewState
    var file: ExcalidrawFile? { state.file }
    var error: Error? { state.error }
    
    var body: some View {
        ZStack {
            if let file {
                ExcalidrawRenderer(file: file)
            } else {
                Color.clear
                    .overlay {
                        ProgressView()
                            .progressViewStyle(.circular)
                    }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}
