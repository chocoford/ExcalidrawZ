//
//  PresentationInspectorPlaceholder.swift
//  ExcalidrawZ
//
//  Created by Codex on 2026/7/27.
//

import SwiftUI

import SFSafeSymbols

struct PresentationInspectorPlaceholder: View {
    enum State {
        case loading
        case empty
        case failed(String)
    }

    let state: State
    var retry: (() -> Void)?

    var body: some View {
        VStack(spacing: spacing) {
            switch state {
                case .loading:
                    ProgressView()
                        .controlSize(.small)
                    Text(localizable: .presentationLoading)
                        .foregroundStyle(.secondary)

                case .empty:
                    Image(systemSymbol: .rectangleStack)
                        .font(.system(size: 28))
                        .foregroundStyle(.secondary)
                    Text(localizable: .presentationNoFramesTitle)
                        .font(.headline)
                    Text(localizable: .presentationNoFramesMessage)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)

                case .failed(let message):
                    Image(systemSymbol: .exclamationmarkTriangle)
                        .font(.system(size: 28))
                        .foregroundStyle(.secondary)
                    Text(localizable: .presentationLoadFailed)
                        .font(.headline)
                    Text(message)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    if let retry {
                        Button(
                            String(localizable: .presentationRefresh),
                            action: retry
                        )
                    }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }

    private var spacing: CGFloat {
        if case .loading = state {
            return 12
        }
        return 10
    }
}
