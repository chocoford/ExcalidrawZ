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
    @MainActor @ViewBuilder
    var inputBox: some View {
        let _ = AIChatRenderDebug.hit("PromptInputView.inputBox")

        let radius = style.cornerRadius
        let core = inputField()
            .overlay {
                if let border = style.border {
                    RoundedRectangle(cornerRadius: radius)
                        .stroke(.separator, lineWidth: border.lineWidth)
                }
            }
            .overlay {
                if isGenerating,
                   style.showsGeneratingEffect,
                   !AIChatRenderDebug.hideGeneratingEffect {
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

    @MainActor @ViewBuilder
    var debugMinimalInputBox: some View {
        PromptDraftInputField(
            draftState: promptDraftState,
            showsAttachments: false,
            sendRequestToken: draftSendRequestToken,
            focus: $isInputFocused,
            onSubmit: { text, images in
                submitDraft(prompt: text, pastedImages: images)
            },
            onPaste: handlePastedItem,
            onSummaryChange: { hasContent, hasImages in
                updateDraftSummary(hasContent: hasContent, hasImages: hasImages)
            }
        )
        .padding(8)
        .background { style.background }
    }

    @MainActor @ViewBuilder
    func inputField() -> some View {
        let _ = AIChatRenderDebug.hit("PromptInputView.inputField")

        VStack(spacing: 0) {
            header

            PromptDraftInputField(
                draftState: promptDraftState,
                showsAttachments: true,
                sendRequestToken: draftSendRequestToken,
                focus: $isInputFocused,
                onSubmit: { text, images in
                    submitDraft(prompt: text, pastedImages: images)
                },
                onPaste: handlePastedItem,
                onSummaryChange: { hasContent, hasImages in
                    updateDraftSummary(hasContent: hasContent, hasImages: hasImages)
                }
            )
        }
        .background { style.background }
    }

    /// Resolve image-bearing TextArea paste events into draft attachments.
    /// The child draft owner appends accepted images and returns
    /// `.action {}` so TextArea inserts nothing into the prompt text: the
    /// prompt stays clean for the model, and the image lives out-of-band
    /// as an attachment.
    ///
    /// Non-image pastes (plain text, web URLs, unknown UTIs, non-image
    /// files) return `nil`, falling through to TextArea's default
    /// handling.
    @MainActor
    func handlePastedItem(_ item: TextAreaPasteItem) -> PromptImagePasteResult {
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

        guard let image else { return .notHandled }
        guard upgradeModelForImageInputIfNeeded() else {
            alertToast(
                AIChatInputCapabilityError.noModelCanReadImages
            )
            return .rejected
        }

        return .accepted(PendingPastedImage(id: UUID(), image: image))
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

enum PromptImagePasteResult {
    case notHandled
    case rejected
    case accepted(PendingPastedImage)
}

@MainActor
private struct PromptDraftInputField: View {
    @EnvironmentObject private var aiChatState: AIChatState
    @ObservedObject var draftState: AIChatPromptDraftState

    let showsAttachments: Bool
    let sendRequestToken: Int
    let focus: FocusState<Bool>.Binding
    let onSubmit: (String, [PendingPastedImage]) -> Bool
    let onPaste: (TextAreaPasteItem) -> PromptImagePasteResult
    let onSummaryChange: (Bool, Bool) -> Void

    private var textBinding: Binding<String> {
        Binding(
            get: { draftState.text },
            set: { draftState.text = $0 }
        )
    }

    private var pastedImagesBinding: Binding<[PendingPastedImage]> {
        Binding(
            get: { draftState.images },
            set: { draftState.images = $0 }
        )
    }

    var body: some View {
        let _ = AIChatRenderDebug.hit("PromptDraftInputField.body")

        VStack(spacing: 0) {
            if showsAttachments {
                AttachmentThumbnailStrip(pastedImages: pastedImagesBinding)
            }

            TextArea(
                text: textBinding,
                placeholder: Text(localizable: .aiChatInputPlaceholder)
            )
            .keyDownHandler(
                TextFieldKeyDownEventHandler(triggers: [(36, nil)]) { event in
                    guard let event else { return nil }
                    if event.keyCode == 36, !event.modifierFlags.contains(.shift) {
                        submit()
                        return nil           // 消费 plain enter
                    }
                    return event             // shift+enter 透传，系统自动插入 \n 并移动光标
                }
            )
            .onPaste { item in
                handlePaste(item)
            }
            .focused(focus)
        }
        .onAppear {
            publishSummary()
        }
        .onChange(of: draftState.text) { _ in
            publishSummary()
        }
        .onChange(of: draftState.images) { _ in
            publishSummary()
        }
        .onChange(of: sendRequestToken) { _ in
            submit()
        }
        .onChange(of: aiChatState.draftRequest?.token) { _ in
            guard let req = aiChatState.draftRequest else { return }
            draftState.text = req.text
            draftState.images = PastedImageHelpers.pendingImages(from: req.files)
            publishSummary()
            focus.wrappedValue = true
        }
        .onChange(of: aiChatState.draftImageAppendRequest?.token) { _ in
            guard let req = aiChatState.draftImageAppendRequest else { return }
            draftState.images.append(contentsOf: req.images)
            publishSummary()
        }
        .onChange(of: aiChatState.editCancelToken) { _ in
            draftState.text = ""
            draftState.images = []
            publishSummary()
            focus.wrappedValue = false
        }
    }

    private func publishSummary() {
        onSummaryChange(draftState.hasContent, draftState.hasImages)
    }

    private func submit() {
        let trimmedText = draftState.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let pastedImages = draftState.images
        guard !trimmedText.isEmpty || !pastedImages.isEmpty else { return }
        guard onSubmit(trimmedText, pastedImages) else { return }
        draftState.text = ""
        draftState.images = []
        publishSummary()
    }

    private func handlePaste(_ item: TextAreaPasteItem) -> TextAreaInsertion? {
        switch onPaste(item) {
            case .notHandled:
                return nil
            case .rejected:
                return .action {}
            case .accepted(let image):
                draftState.images.append(image)
                publishSummary()
                return .action {}
        }
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
