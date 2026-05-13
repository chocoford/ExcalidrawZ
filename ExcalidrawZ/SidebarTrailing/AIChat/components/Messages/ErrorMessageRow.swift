//
//  ErrorMessageRow.swift
//  ExcalidrawZ
//
//  Created by Chocoford on 5/4/26.
//

import SwiftUI

struct ErrorMessageRow: View {
    let error: String
    /// Retries the failed generation. Error rows usually represent
    /// LLMKit's tail `.error` stub, so the parent resumes the current
    /// conversation instead of regenerating from an earlier message.
    var onRetry: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemSymbol: .exclamationmarkTriangleFill)
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
                        Label(.localizable(.generalButtonRetry), systemSymbol: .arrowClockwise)
                            .font(.caption)
                    }
                    .help(.generalButtonRetry)
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
