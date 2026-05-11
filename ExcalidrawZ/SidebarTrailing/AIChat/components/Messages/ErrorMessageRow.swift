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
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.top, 2)

                Text(error)
                    .font(.callout)
                    .foregroundStyle(.primary)
                    .lineLimit(5)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }

            HStack(spacing: 6) {
                CopyButton(text: error)

                if let onRetry {
                    Button {
                        onRetry()
                    } label: {
                        Label("Retry", systemImage: "arrow.clockwise")
                            .font(.caption)
                    }
                    .help("Retry")
                }
            }
            .buttonStyle(.text(size: .small, square: false))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            if #available(macOS 26.0, iOS 26.0, *) {
                RoundedRectangle(cornerRadius: 18)
                    .fill(.clear)
                    .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 18))
            } else {
                RoundedRectangle(cornerRadius: 14)
                    .fill(.regularMaterial)
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 18)
                .stroke(Color.red.opacity(0.18), lineWidth: 0.5)
        }
    }
}
