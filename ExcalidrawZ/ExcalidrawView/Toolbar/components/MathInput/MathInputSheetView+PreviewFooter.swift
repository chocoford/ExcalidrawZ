//
//  MathInputSheetView+PreviewFooter.swift
//  ExcalidrawZ
//
//  Created by Codex on 2026/06/19.
//

import SwiftUI
import ChocofordUI
import SFSafeSymbols

extension MathInputSheetView {
    @ViewBuilder
    var commitButtonLabel: some View {
        switch mode {
            case .insert:
                Text(.localizable(.toolbarLatexMathButtonInsert))
            case .edit:
                Text(.localizable(.generalButtonSave))
        }
    }

    @ViewBuilder
    var previewArea: some View {
        if activeWorkspace == .function {
            previewCard(cornerRadius: 28)
                .aspectRatio(1, contentMode: .fit)
                .frame(maxWidth: 420)
                .frame(maxWidth: .infinity, alignment: .center)
        } else {
            previewCard(cornerRadius: 12)
                .frame(height: 168)
        }
    }

    func previewCard(cornerRadius: CGFloat) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Color(excalidrawString: canvasBackgroundColor))
                .apply { content in
                    if canvasColorScheme == .dark {
                        content
                            .colorInvert()
                            .hueRotation(Angle(degrees: 180))
                    } else {
                        content
                    }
                }
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(Color.primary.opacity(canvasColorScheme == .dark ? 0.18 : 0.1))
                }

            previewContent
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    @ViewBuilder
    var previewContent: some View {
        if let error {
            Text(errorDescription(for: error))
                .font(.callout)
                .multilineTextAlignment(.center)
                .foregroundStyle(.red)
                .padding()
        } else if let svgContent {
            FittedSVGPreviewView(
                svg: svgContent.svg,
                padding: 18,
                cssFilter: previewCanvasFilter,
                backgroundColor: canvasBackgroundColor,
                backgroundFilter: previewCanvasFilter
            )
        } else {
            Text(.localizable(.toolbarLatexMathInsertSheetPreviewTitle))
                .font(.title3)
                .foregroundStyle(.secondary)
        }
    }

    var previewCanvasFilter: String? {
        canvasColorScheme == .dark ? "invert(1) hue-rotate(180deg)" : nil
    }

    func commitRenderedSVG() {
        guard let svgContent else { return }
        onCommit(svgContent)
        dismiss()
    }

    var footer: some View {
        HStack(spacing: 12) {
            Spacer(minLength: 0)

            Button {
                dismiss()
            } label: {
                Text(.localizable(.generalButtonCancel))
                    .frame(minWidth: 96)
            }

            Button {
                commitRenderedSVG()
            } label: {
                commitButtonLabel
                    .frame(minWidth: 112)
            }
            .modernButtonStyle(style: .glassProminent)
            .disabled(svgContent == nil)
        }
        .modernButtonStyle(size: .large, shape: .modern)
        .padding(16)
    }
}
