//
//  ErrorMessageRow.swift
//  ExcalidrawZ
//
//  Created by Chocoford on 5/4/26.
//

import SwiftUI

struct ErrorMessageRow: View {
    let error: String
    /// Re-runs the user message that triggered this error. Wired by the
    /// parent so it can resolve the right turn to regenerate from. Nil when
    /// no preceding user message exists (rare — error without prompt).
    var onRetry: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(error)
                .foregroundStyle(.red)
                .textSelection(.enabled)

            HStack(spacing: 0) {
                CopyButton(text: error)

                if let onRetry {
                    Button {
                        onRetry()
                    } label: {
                        Image(systemName: "arrow.clockwise").font(.caption)
                    }
                    .foregroundStyle(.secondary)
                    .help("Retry")
                }
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.text(size: .small, square: true))
        }
    }
}
