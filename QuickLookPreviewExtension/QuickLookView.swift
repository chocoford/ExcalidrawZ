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

    @AppStorage(
        SharedAppAppearanceStore.appearanceKey,
        store: SharedAppAppearanceStore.defaults
    ) private var appearanceRawValue = SharedAppAppearance.auto.rawValue

    @ObservedObject var state: PreviewState
    var file: ExcalidrawFile? { state.file }
    var error: Error? { state.error }

    private var preferredColorScheme: ColorScheme? {
        switch SharedAppAppearance(rawValue: appearanceRawValue) ?? .auto {
            case .light:
                return .light
            case .dark:
                return .dark
            case .auto:
                return nil
        }
    }
    
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
        .preferredColorScheme(preferredColorScheme)
    }
}
