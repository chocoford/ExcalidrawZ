//
//  PromptInputView+ImagePaste.swift
//  ExcalidrawZ
//
//  Image-paste support for `PromptInputView`. Modeled on the ChatGPT
//  macOS client: pasted images do *not* go inside the text — they
//  appear as a row of thumbnails above the input field, each with its
//  own delete affordance, and ride along to the user message as
//  attachments on send.
//
//  Why no inline tokens (the previous design): inline tokens looked
//  cute but conflate two concerns — composing a prompt and selecting
//  attachments. Users pastes a screenshot to *show* the model
//  something; they don't want the placeholder living inside their
//  prose. Out-of-band thumbnails match every modern chat UI and let
//  the prompt text stay clean.
//
//  Data flow:
//
//  1. TextArea's `.onPaste(_:)` handler captures image-bearing items,
//     appends a `PendingPastedImage` to side-state, and returns
//     `.action {}` so TextArea inserts nothing into the text.
//  2. The strip view (`AttachmentThumbnailStrip`) renders the
//     side-state as little chips above the input.
//  3. On send, every entry in the side-state is encoded as a
//     `data:image/png;base64,...` URI and attached to the user
//     message via `ChatMessageContent.files`.
//  4. From there the existing pipeline takes over: LLMKit's automatic
//     upload provider may rewrite base64 → URL, the persistence
//     layer's `AIChatAttachmentRepository` writes either form to
//     iCloud-Drive-synced storage and roundtrips it on restore.
//
//  iOS note: TextArea's paste pipeline is currently macOS-only (per
//  the SDK docs); the `.onPaste` handler simply doesn't fire on iOS.
//  The code below still compiles on iOS because `PlatformImage` is a
//  cross-platform alias and we only diverge in the rendering call.
//

import SwiftUI
import ChocofordUI
import LLMCore
import SFSafeSymbols

#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

// MARK: - Side-state record

/// One pasted image, paired with a stable id so SwiftUI's `ForEach`
/// can identify it across removals and the user's "remove" tap can
/// resolve back to the right entry.
struct PendingPastedImage: Identifiable, Equatable {
    let id: UUID
    let image: PlatformImage

    static func == (lhs: PendingPastedImage, rhs: PendingPastedImage) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Encoding helpers

enum PastedImageHelpers {
    /// `PlatformImage` → `data:image/png;base64,...` URI. PNG so we
    /// keep alpha (screenshots often have it) and don't worry about
    /// JPEG quality knobs. The URI is the form
    /// `ChatMessageContent.File.base64EncodedImage` carries verbatim
    /// — LLMKit's upload provider parses the mediaType from the
    /// prefix.
    static func encodeAsDataURI(_ image: PlatformImage) -> String? {
#if canImport(AppKit)
        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:]) else {
            return nil
        }
        return "data:image/png;base64,\(png.base64EncodedString())"
#elseif canImport(UIKit)
        guard let png = image.pngData() else { return nil }
        return "data:image/png;base64,\(png.base64EncodedString())"
#else
        return nil
#endif
    }

    /// Build the `[File]` payload for a user message from the current
    /// pastedImages. Encoding failures drop that one entry silently —
    /// the message itself shouldn't be blocked by one corrupted
    /// attachment.
    static func buildFiles(
        from pastedImages: [PendingPastedImage]
    ) -> [ChatMessageContent.File] {
        pastedImages.compactMap { entry in
            guard let dataURI = encodeAsDataURI(entry.image) else { return nil }
            return .base64EncodedImage(dataURI)
        }
    }

    /// Rehydrate persisted message attachments back into input thumbnails
    /// when editing an older user message.
    static func pendingImages(
        from files: [ChatMessageContent.File]
    ) -> [PendingPastedImage] {
        files.compactMap { file in
            guard let image = platformImage(from: file) else { return nil }
            return PendingPastedImage(id: UUID(), image: image)
        }
    }

    private static func platformImage(from file: ChatMessageContent.File) -> PlatformImage? {
        switch file {
            case .base64EncodedImage(let value):
                let payload = value.split(separator: ",", maxSplits: 1).last.map(String.init) ?? value
                guard let data = Data(base64Encoded: payload) else { return nil }
#if canImport(AppKit)
                return NSImage(data: data)
#elseif canImport(UIKit)
                return UIImage(data: data)
#else
                return nil
#endif
            case .image(let url):
                guard let data = try? Data(contentsOf: url) else { return nil }
#if canImport(AppKit)
                return NSImage(data: data)
#elseif canImport(UIKit)
                return UIImage(data: data)
#else
                return nil
#endif
        }
    }
}

extension ChatMessageContent.File {
    var isImageInput: Bool {
        switch self {
            case .base64EncodedImage, .image:
                return true
        }
    }
}

extension Array where Element == ChatMessageContent.File {
    var containsImageInput: Bool {
        contains { $0.isImageInput }
    }
}

// MARK: - Thumbnail strip

/// Horizontal row of pasted-image thumbnails, each with a hover-
/// revealed ✕ delete button. Sits above the TextArea inside the
/// input chrome (the ChatGPT layout) so it visually reads as
/// "what's about to be sent" rather than as standalone media.
///
/// Self-collapsing: when there are no images, returns an `EmptyView`
/// so the host doesn't have to gate it conditionally — drop in once,
/// it's invisible until something gets pasted.
struct AttachmentThumbnailStrip: View {
    @Binding var pastedImages: [PendingPastedImage]

    var body: some View {
        if !pastedImages.isEmpty {
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(pastedImages) { entry in
                        // Each tile is its own view so per-tile hover
                        // state can live next to the tile — sharing
                        // a single `@State` at strip level would mean
                        // hovering any tile reveals every ✕.
                        AttachmentThumbnailTile(
                            entry: entry,
                            onRemove: { remove(entry.id) }
                        )
                    }
                    .padding(.horizontal, 12)
                }
                .scrollIndicators(.hidden)
                .padding(.top, 10)
                // Bottom padding intentionally small — the TextArea
                // sits right below; we want a single visual block.
                .padding(.bottom, 6)
            }
        }
    }

    private func remove(_ id: UUID) {
        withAnimation(.easeInOut(duration: 0.15)) {
            pastedImages.removeAll { $0.id == id }
        }
    }
}

/// Single thumbnail with its own hover state. The ✕ is hidden by
/// default and fades in when the cursor enters the tile —
/// mirrors ChatGPT's macOS client where attachments stay visually
/// quiet until you reach for them.
private struct AttachmentThumbnailTile: View {
    let entry: PendingPastedImage
    let onRemove: () -> Void

    /// Side length of each thumbnail tile, in points. ChatGPT-ish
    /// proportions; small enough to fit several in the input chrome
    /// without dominating the prompt area.
    private let tileSize: CGFloat = 56

    @State private var isHovering: Bool = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            // The image itself — rounded card, fixed square aspect.
            // Using `.scaledToFill` + clip so portrait/landscape both
            // present as a clean tile rather than letterboxing.
#if canImport(AppKit)
            Image(nsImage: entry.image)
                .resizable()
                .scaledToFill()
                .frame(width: tileSize, height: tileSize)
                .clipShape(RoundedRectangle(cornerRadius: 8))
#elseif canImport(UIKit)
            Image(uiImage: entry.image)
                .resizable()
                .scaledToFill()
                .frame(width: tileSize, height: tileSize)
                .clipShape(RoundedRectangle(cornerRadius: 8))
#endif

            // ✕ delete button. Hidden until hover, then fades in.
            // Anchored half-outside the tile so it reads as an
            // affordance attached to the image rather than overlapping
            // its content. `allowsHitTesting(isHovering)` ensures the
            // invisible button doesn't swallow clicks meant for the
            // image when hidden — important on iOS where there's no
            // hover and we'd otherwise have a phantom hitbox.
            Button(action: onRemove) {
                Label(
                    .localizable(.aiChatButtonRemoveAttachment),
                    systemSymbol: .xmarkCircleFill
                )
                .font(.system(size: 16))
                .symbolRenderingMode(.palette)
                .foregroundStyle(.white, .black.opacity(0.55))
                .labelStyle(.iconOnly)
            }
            .buttonStyle(.plain)
            .offset(x: 6, y: -6)
            .opacity(isHovering ? 1 : 0)
            .allowsHitTesting(isHovering)
            .animation(.easeInOut(duration: 0.12), value: isHovering)
            .help(.localizable(.aiChatButtonRemoveAttachment))
        }
        .padding(.top, 6)
        .padding(.trailing, 6)
        .onHover { hovering in
            isHovering = hovering
        }
    }
}
