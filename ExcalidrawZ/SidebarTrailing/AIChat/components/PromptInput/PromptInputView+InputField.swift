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
import UniformTypeIdentifiers
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

    @ViewBuilder
    var debugMinimalInputBox: some View {
        PromptDraftInputField(
            draftKey: promptDraftKey,
            draftState: promptDraftState,
            showsAttachments: false,
            sendRequestToken: draftSendRequestToken,
            maxTextAreaHeight: nil,
            textInsets: nil,
            linesOverflow: nil,
            onTextAreaSingleLineChanged: nil,
            focus: $isInputFocused,
            onSubmit: { text, images in
                submitDraft(prompt: text, pastedImages: images)
            },
            onPaste: handlePastedItem,
            onSummaryChange: { hasContent, hasImages in
                updateDraftSummary(hasContent: hasContent, hasImages: hasImages)
            }
        )
        .id(ObjectIdentifier(promptDraftState))
        .padding(8)
        .background { style.background }
    }

    @ViewBuilder
    func inputField() -> some View {
        let _ = AIChatRenderDebug.hit("PromptInputView.inputField")

        VStack(spacing: 0) {
            header

            PromptDraftInputField(
                draftKey: promptDraftKey,
                draftState: promptDraftState,
                showsAttachments: true,
                sendRequestToken: draftSendRequestToken,
                maxTextAreaHeight: nil,
                textInsets: nil,
                linesOverflow: nil,
                onTextAreaSingleLineChanged: nil,
                focus: $isInputFocused,
                onSubmit: { text, images in
                    submitDraft(prompt: text, pastedImages: images)
                },
                onPaste: handlePastedItem,
                onSummaryChange: { hasContent, hasImages in
                    updateDraftSummary(hasContent: hasContent, hasImages: hasImages)
                }
            )
            .id(ObjectIdentifier(promptDraftState))
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
struct PromptDraftInputField: View {
    @Environment(AIChatState.self) private var aiChatState
    let draftKey: String
    @Bindable var draftState: AIChatPromptDraftState

    let showsAttachments: Bool
    let sendRequestToken: Int
    let maxTextAreaHeight: CGFloat?
    let textInsets: EdgeInsets?
    let linesOverflow: Binding<Bool>?
    let onTextAreaSingleLineChanged: ((Bool) -> Void)?
    let focus: FocusState<Bool>.Binding
    var autofocus: Bool = false
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

            PromptDraftTextArea(
                text: textBinding,
                maxHeight: maxTextAreaHeight,
                textInsets: textInsets,
                linesOverflow: linesOverflow,
                onSingleLineChanged: onTextAreaSingleLineChanged,
                focus: focus,
                autofocus: autofocus,
                onSubmit: submit,
                onPaste: handlePaste
            )
        }
        .onAppear {
            publishSummary()
        }
        .watch(value: draftState.text) {
            publishSummary()
        }
        .watch(value: draftState.images) {
            publishSummary()
        }
        .watch(value: sendRequestToken) {
            submit()
        }
        .watch(value: aiChatState.draftRequest?.token) {
            handleDraftRequest(aiChatState.draftRequest)
        }
        .watch(value: aiChatState.draftImageAppendRequest?.token) {
            handleDraftImageAppendRequest(aiChatState.draftImageAppendRequest)
        }
        .watch(value: aiChatState.editCancelRequest?.token) {
            handleEditCancelRequest(aiChatState.editCancelRequest)
        }
        .onDrop(
            of: PromptDraftInputDrop.supportedTypeIdentifiers,
            isTargeted: nil,
            perform: handleDrop
        )
    }

    private func handleDraftRequest(_ req: AIChatState.DraftRequest?) {
        guard let req else { return }
        let requestDraftKey: String? = req.draftKey
        guard targetsThisDraft(requestDraftKey) else { return }
        guard draftState.shouldHandleDraftRequest(token: req.token) else { return }

        if isGlobalDraftRequest(requestDraftKey) {
            draftState.text = req.text
            draftState.images = PastedImageHelpers.pendingImages(from: req.files)
            publishSummary()
        }
        focus.wrappedValue = true
    }

    private func handleDraftImageAppendRequest(_ req: AIChatState.DraftImageAppendRequest?) {
        guard let req else { return }
        let requestDraftKey: String? = req.draftKey
        guard targetsThisDraft(requestDraftKey) else { return }
        guard draftState.shouldHandleDraftImageAppendRequest(token: req.token) else { return }

        if isGlobalDraftRequest(requestDraftKey) {
            let imagesToAppend: [PendingPastedImage] = req.images
            draftState.images += imagesToAppend
            publishSummary()
        }
    }

    private func handleEditCancelRequest(_ req: AIChatState.EditCancelRequest?) {
        guard let req else { return }
        let requestDraftKey: String? = req.draftKey
        guard targetsThisDraft(requestDraftKey) else { return }
        guard draftState.shouldHandleEditCancel(token: req.token) else { return }

        if isGlobalDraftRequest(requestDraftKey) {
            draftState.text = ""
            draftState.images = []
            publishSummary()
        }
        focus.wrappedValue = false
    }

    private func targetsThisDraft(_ requestDraftKey: String?) -> Bool {
        guard let requestDraftKey else { return true }
        return requestDraftKey == draftKey
    }

    private func isGlobalDraftRequest(_ requestDraftKey: String?) -> Bool {
        requestDraftKey == nil
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
                if case .url(let url) = item {
                    return .text(url.absoluteString)
                }
                return nil
            case .rejected:
                return .action {}
            case .accepted(let image):
                draftState.images.append(image)
                publishSummary()
                return .action {}
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        let supportedProviders = providers.filter { provider in
            PromptDraftInputDrop.supportedTypeIdentifiers.contains { typeIdentifier in
                provider.hasItemConformingToTypeIdentifier(typeIdentifier)
            }
        }
        guard !supportedProviders.isEmpty else { return false }

        Task {
            for provider in supportedProviders {
                let items = await PromptDraftInputDrop.loadItems(from: provider)
                for item in items {
                    handleDroppedItem(item)
                }
            }
        }
        return true
    }

    private func handleDroppedItem(_ item: TextAreaPasteItem) {
        switch onPaste(item) {
            case .notHandled:
                if case .url(let url) = item {
                    appendDroppedText(url.absoluteString)
                }
            case .rejected:
                break
            case .accepted(let image):
                draftState.images.append(image)
                publishSummary()
        }
    }

    private func appendDroppedText(_ value: String) {
        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedValue.isEmpty else { return }

        if draftState.text.isEmpty {
            draftState.text = trimmedValue
        } else {
            draftState.text += "\n\(trimmedValue)"
        }
        publishSummary()
    }
}

private enum PromptDraftInputDrop {
    static let supportedTypeIdentifiers: [String] = [
        UTType.image.identifier,
        UTType.fileURL.identifier,
        UTType.url.identifier
    ]

    static func loadItems(from provider: NSItemProvider) async -> [TextAreaPasteItem] {
        if let image = await loadImage(from: provider) {
            return [.image(image)]
        }
        if let fileURL = await loadURL(from: provider, type: .fileURL), fileURL.isFileURL {
            return [.fileURL(fileURL)]
        }
        if let url = await loadURL(from: provider, type: .url), !url.isFileURL {
            return [.url(url)]
        }
        return []
    }

    private static func loadImage(from provider: NSItemProvider) async -> PlatformImage? {
        guard provider.hasItemConformingToTypeIdentifier(UTType.image.identifier),
              let data = await loadData(from: provider, typeIdentifier: UTType.image.identifier)
        else { return nil }

#if canImport(AppKit)
        return NSImage(data: data)
#elseif canImport(UIKit)
        return UIImage(data: data)
#else
        return nil
#endif
    }

    private static func loadData(
        from provider: NSItemProvider,
        typeIdentifier: String
    ) async -> Data? {
        await withCheckedContinuation { continuation in
            provider.loadDataRepresentation(forTypeIdentifier: typeIdentifier) { data, _ in
                continuation.resume(returning: data)
            }
        }
    }

    private static func loadURL(
        from provider: NSItemProvider,
        type: UTType
    ) async -> URL? {
        guard provider.hasItemConformingToTypeIdentifier(type.identifier) else { return nil }
        return await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: type.identifier, options: nil) { item, _ in
                continuation.resume(returning: url(from: item))
            }
        }
    }

    private static func url(from item: NSSecureCoding?) -> URL? {
        if let url = item as? URL {
            return url
        }
        if let url = item as? NSURL {
            return url as URL
        }
        if let data = item as? Data {
            return URL(dataRepresentation: data, relativeTo: nil)
        }
        if let string = item as? String {
            return URL(string: string)
        }
        return nil
    }
}

@MainActor
private struct PromptDraftTextArea: View {
    let text: Binding<String>
    let maxHeight: CGFloat?
    let textInsets: EdgeInsets?
    let linesOverflow: Binding<Bool>?
    let onSingleLineChanged: ((Bool) -> Void)?
    let focus: FocusState<Bool>.Binding
    var autofocus: Bool = false
    let onSubmit: () -> Void
    let onPaste: (TextAreaPasteItem) -> TextAreaInsertion?

    var body: some View {
        configuredTextArea
            .focused(focus)
    }

    private var configuredTextArea: TextArea {
        var textArea = TextArea(
            text: text,
            placeholder: Text(localizable: .aiChatInputPlaceholder)
        )
        .onPaste { item in
            onPaste(item)
        }
        .promptInputSubmitOnReturn(onSubmit)

        if let maxHeight {
            textArea = textArea.maxHeight(maxHeight)
        }
        if let textInsets {
            textArea = textArea.textInsets(textInsets)
        }
        if let linesOverflow {
            textArea = textArea.linesOverflow(linesOverflow)
        }
        if let onSingleLineChanged {
            textArea = textArea.onSingleLineChanged(onSingleLineChanged)
        }
        textArea = textArea.autofocus(autofocus)
        return textArea
    }
}

private extension TextArea {
    func promptInputSubmitOnReturn(_ submit: @escaping () -> Void) -> TextArea {
#if os(iOS)
        self.submitOnReturn(sources: .hardwareKeyboard, submit)
#else
        self.submitOnReturn(submit)
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
