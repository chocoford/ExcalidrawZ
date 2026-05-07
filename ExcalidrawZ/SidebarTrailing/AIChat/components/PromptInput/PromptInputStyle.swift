//
//  PromptInputStyle.swift
//  ExcalidrawZ
//
//  Visual configuration for `PromptInputView` — extracted from the
//  main view file so the style lookup table doesn't bloat the input
//  view's struct definition. Contains:
//
//   - `PromptInputStyle<Background>`: the value type carrying chrome
//     knobs (banner, corner radius, shadow, border, custom backdrop).
//   - `PromptInputStyle.inspector` / `.island`: the two presets the
//     app actually instantiates today.
//   - `PlatformDefaultPromptBackground`: typed sentinel `View` used
//     when the caller doesn't supply a custom backdrop, so the style
//     stays generic without falling back to `AnyView`.
//

import SwiftUI

/// Visual knobs for `PromptInputView`. Lets callers tune the prompt block to
/// the chrome it's embedded in — the inspector panel wants prominent shadow,
/// border and the low-credits banner; the floating island shares the same
/// chassis but trims the chrome.
///
/// `Background` is a concrete `View` type rather than `AnyView` so the input
/// box's `.background { … }` propagates layout proposals normally — type
/// erasure was creating a class of subtle frame-clipping issues. The platform
/// default is materialized as a typed sentinel view (`PlatformDefaultPromptBackground`)
/// so presets that want it don't need a closure.
struct PromptInputStyle<Background: View> {
    /// Whether the "Only N credits left" hint above the input is visible.
    /// Hosts with limited vertical space usually turn this off.
    var showsLowCreditsBanner: Bool

    /// Corner radius for the input field and its border/banner.
    var cornerRadius: CGFloat

    /// Drop-shadow under the input field. `nil` disables the shadow entirely.
    var shadow: ShadowSpec?

    /// Hairline border around the input field. `nil` disables the border.
    var border: BorderSpec?

    /// View painted behind the input field. The view receives the input's
    /// frame; include whatever shape/clip you want it to take. Typically a
    /// `RoundedRectangle(cornerRadius: cornerRadius)` so the corners match
    /// `border`.
    var background: Background

    /// Caller supplies a custom backdrop via `@ViewBuilder`.
    init(
        showsLowCreditsBanner: Bool = true,
        cornerRadius: CGFloat = 20,
        shadow: ShadowSpec? = ShadowSpec(opacity: 0.2, radius: 4),
        border: BorderSpec? = BorderSpec(lineWidth: 0.5),
        @ViewBuilder background: () -> Background
    ) {
        self.showsLowCreditsBanner = showsLowCreditsBanner
        self.cornerRadius = cornerRadius
        self.shadow = shadow
        self.border = border
        self.background = background()
    }

    struct ShadowSpec {
        var color: Color = .black
        var opacity: Double = 0.2
        var radius: CGFloat = 4

        init(color: Color = .black, opacity: Double = 0.2, radius: CGFloat = 4) {
            self.color = color
            self.opacity = opacity
            self.radius = radius
        }
    }

    struct BorderSpec {
        var lineWidth: CGFloat = 0.5
    }
}

// MARK: - Platform-default convenience

extension PromptInputStyle where Background == PlatformDefaultPromptBackground {
    /// Closure-less init: backdrop falls back to `PlatformDefaultPromptBackground`,
    /// which paints glass on macOS 26+ / iOS 26+ and regularMaterial below.
    /// Most call sites should use this — only reach for the `@ViewBuilder`
    /// init when you actually need a non-default backdrop.
    init(
        showsLowCreditsBanner: Bool = true,
        cornerRadius: CGFloat = 20,
        shadow: ShadowSpec? = ShadowSpec(opacity: 0.2, radius: 4),
        border: BorderSpec? = BorderSpec(lineWidth: 0.5)
    ) {
        self.init(
            showsLowCreditsBanner: showsLowCreditsBanner,
            cornerRadius: cornerRadius,
            shadow: shadow,
            border: border,
            background: {
                PlatformDefaultPromptBackground(cornerRadius: cornerRadius)
            }
        )
    }

    /// Default — used by `AIChatView` inside the inspector. Full chrome,
    /// shows the credits hint, platform-default background.
    static var inspector: PromptInputStyle<PlatformDefaultPromptBackground> {
        PromptInputStyle()
    }

    /// Tuned for `AIChatIslandView`. Same backdrop as the inspector (so the
    /// glass rim on macOS 26+ gives the text its visual padding), just with
    /// the credits banner / shadow trimmed because the island provides its
    /// own outer chrome.
    static var island: PromptInputStyle<PlatformDefaultPromptBackground> {
         PromptInputStyle(
             showsLowCreditsBanner: false,
             cornerRadius: 24,
             shadow: .init(color: .clear, radius: 0),
             border: BorderSpec(lineWidth: 0)
         )
    }
}

/// Glass on macOS 26+ / iOS 26+, `regularMaterial` below. Materialized as a
/// concrete `View` so `PromptInputStyle` can stay generic without falling
/// back to `AnyView` — the input field's `.background` then propagates
/// layout proposals cleanly.
struct PlatformDefaultPromptBackground: View {
    let cornerRadius: CGFloat

    var body: some View {
        if #available(macOS 26.0, iOS 26.0, *) {
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(Color.textBackgroundColor)
                .glassEffect(in: RoundedRectangle(cornerRadius: cornerRadius))
        } else {
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(.regularMaterial)
        }
    }
}
