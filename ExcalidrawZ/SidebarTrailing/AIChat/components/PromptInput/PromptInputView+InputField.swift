//
//  PromptInputView+InputField.swift
//  ExcalidrawZ
//
//  Text + paste handling for `PromptInputView`. Extracted from the
//  main file because the input box has its own little world: composite
//  layout (thumbnail strip + TextArea), key-event interception for
//  Enter / Shift+Enter, paste-to-attachment plumbing, and a small
//  cross-platform `PlatformImage` resolver. Keeping it separate makes
//  the main file's `body` read at the right altitude.
//

import SwiftUI
import ChocofordUI
#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

extension PromptInputView {
    /// Input box layered to honor the active `PromptInputStyle`: background,
    /// corner-rounded border, optional shadow. `style.background` is a
    /// concrete `View` (no `AnyView`, no `Optional`), so the modifier chain
    /// is a single straight pass — SwiftUI's layout proposals reach the
    /// backdrop intact.
    ///
    /// `.shadow` is applied via a real `if let` rather than the previous
    /// `.shadow(color: .clear, radius: 0)` fallback: SwiftUI still spins up
    /// a shadow effect layer even when all parameters are zero-equivalent,
    /// which left a faint compositing artifact in island mode.
    @ViewBuilder
    var inputBox: some View {
        let radius = style.cornerRadius
        let core = inputField()
            .overlay {
                if let border = style.border {
                    RoundedRectangle(cornerRadius: radius)
                        .stroke(.separator, lineWidth: border.lineWidth)
                }
            }
            .overlay {
                if isGenerating, style.showsGeneratingEffect {
                    GeneratingPromptInputEffect(cornerRadius: radius)
                        // Fade-in is driven internally by the effect's
                        // `TimelineView` (smoothstepped against mount
                        // time). We only need an external transition
                        // for the *removal* path so the effect doesn't
                        // pop off when generation ends.
                        .transition(.asymmetric(
                            insertion: .identity,
                            removal: .opacity
                        ))
                }
            }
            .animation(.easeInOut(duration: 0.25), value: isGenerating)

        if let shadow = style.shadow {
            core
                .compositingGroup()
                .shadow(
                    color: shadow.color.opacity(shadow.opacity),
                    radius: shadow.radius
                )
        } else {
            core
        }
    }

    @ViewBuilder
    func inputField() -> some View {
        if #available(macOS 15.0, iOS 18.0, *) {
            // Composite: thumbnail strip sits *inside* the rounded
            // chrome above the TextArea so they read as one unit
            // ("attachments + prompt about to be sent"). Background
            // applies to the whole stack — the strip and the text
            // share the same backdrop, no seams.
            VStack(spacing: 0) {
                AttachmentThumbnailStrip(pastedImages: $pastedImages)

                TextArea(
                    text: $inputText,
                    placeholder: Text("Ask AI to draw...")
                )
                .keyDownHandler(
                    TextFieldKeyDownEventHandler(triggers: [(36, nil)]) { event in
                        guard let event else { return nil }
                        if event.keyCode == 36, !event.modifierFlags.contains(.shift) {
                            sendMessage()
                            return nil           // 消费 plain enter
                        }
                        return event             // shift+enter 透传，系统自动插入 \n 并移动光标
                    }
                )
                .onPaste { item in
                    handlePastedItem(item)
                }
                .focused($isInputFocused)
            }
            .background { style.background }
        } else {
            TextEditor(text: $inputText)
                .frame(height: 160)
                .focused($isInputFocused)
        }
    }

    /// Convert a TextArea paste event into the right `TextAreaInsertion`.
    /// Image-bearing items get captured into `pastedImages` (which the
    /// thumbnail strip above the input renders); we return
    /// `.action {}` so TextArea inserts nothing into the prompt text
    /// — the prompt stays clean for the model, and the image lives
    /// out-of-band as an attachment.
    ///
    /// Non-image pastes (plain text, web URLs, unknown UTIs, non-image
    /// files) return `nil`, falling through to TextArea's default
    /// handling.
    func handlePastedItem(_ item: TextAreaPasteItem) -> TextAreaInsertion? {
        let image: PlatformImage?
        switch item {
            case .image(let img):
                image = img
            case .fileURL(let url):
                // Best-effort image load. Non-image fileURLs (PDFs,
                // arbitrary docs) currently return nil — we have
                // nothing useful to do with them yet. When generic
                // file uploads land, this is where to grow.
                image = imageFromFileURL(url)
            default:
                image = nil
        }

        guard let image else { return nil }

        // Append synchronously so a same-runloop send picks it up.
        pastedImages.append(PendingPastedImage(id: UUID(), image: image))
        // No-op action to swallow the paste — TextArea inserts nothing.
        return .action {}
    }

    /// Try to turn a file URL into a `PlatformImage`. macOS reads
    /// almost any image format via NSImage; on iOS we go through Data
    /// + UIImage. Returns nil for non-image data (or unreadable
    /// files), so callers can fall through to default paste handling.
    func imageFromFileURL(_ url: URL) -> PlatformImage? {
#if canImport(AppKit)
        return NSImage(contentsOf: url)
#elseif canImport(UIKit)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return UIImage(data: data)
#else
        return nil
#endif
    }
}

private struct GeneratingPromptInputEffect: View {
    let cornerRadius: CGFloat

    @Environment(\.colorScheme) private var colorScheme

    /// Captured at view mount. We compute fade-in elapsed time inside
    /// `TimelineView` against this so the effect ramps up from fully
    /// transparent without needing an external `.transition` /
    /// `.animation` on the call site — everything is one TimelineView
    /// driven sample.
    @State private var mountedAt: Date = Date()

    /// How long the fade-in takes once the effect mounts.
    private static let fadeInDuration: TimeInterval = 0.55

    var body: some View {
        TimelineView(.animation) { context in
            let phase = context.date.timeIntervalSinceReferenceDate
            let elapsed = context.date.timeIntervalSince(mountedAt)
            // Smoothstep so the fade-in eases at both ends instead of
            // ramping linearly.
            let raw = max(0, min(1, elapsed / Self.fadeInDuration))
            let fadeIn = raw * raw * (3 - 2 * raw)

            let rotation = Angle.degrees((phase.truncatingRemainder(dividingBy: 4.2) / 4.2) * 360)
            let pulse = 0.45 + 0.25 * sin(phase * 1.45)
            let palette = palette(for: colorScheme)
            let gradient = AngularGradient(
                colors: palette.gradientStops,
                center: .center,
                angle: rotation
            )

            RoundedRectangle(cornerRadius: cornerRadius)
                .strokeBorder(gradient, lineWidth: 0.9)
                .opacity(palette.borderOpacity)
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .stroke(gradient, lineWidth: 12)
                        .blur(radius: 8)
                        .opacity(palette.innerGlowBase + pulse * palette.innerGlowPulse)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .stroke(gradient, lineWidth: 24)
                        .blur(radius: 20)
                        .opacity(palette.midGlowBase + pulse * palette.midGlowPulse)
                }
                .overlay {
                    // Outermost halo. In light mode this is a near-white
                    // bloom that reads as luminance against the bright
                    // page; in dark mode the same white halo would clip
                    // the highlights and look blown-out, so we drop it
                    // way down and shift the tint toward the accent hue
                    // — the rim still glows, but it glows *colored*
                    // instead of *bright*.
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .stroke(palette.haloColor.opacity(palette.haloBase + pulse * palette.haloPulse), lineWidth: 34)
                        .blur(radius: 34)
                }
                .opacity(fadeIn)
                .allowsHitTesting(false)
        }
    }

    /// Per-color-scheme palette. Light mode pushes everything toward
    /// white (low saturation, near-opaque) so the rim reads as bright
    /// luminance against a bright surface. Dark mode keeps the same hue
    /// rotation but bumps saturation back up and trims opacity — over a
    /// dark background, low-sat colors muddy the result and a strong
    /// white halo blows out the highlights, so we let the colors carry
    /// more chroma and let the dark bg do the contrast work.
    private func palette(for scheme: ColorScheme) -> AIAppearancePalette.GeneratingPromptInputPalette {
        AIAppearancePalette.generatingPromptInputPalette(for: scheme)
    }
}
