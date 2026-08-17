import SwiftUI

/// Product-wide semantic palette for Goku. The colors borrow the recognizable
/// gi-orange / blue / energy-gold rhythm while keeping the UI native, quiet, and
/// readable in both system appearances.
enum GokuVisualTheme {
    static let giOrangeHex = "#F47A21"
    static let royalBlueHex = "#2166F3"
    static let energyGoldHex = "#FFD54A"
    static let deepNavyHex = "#071426"
    static let skyBlueHex = "#73D5FF"
    static let primaryActionForegroundHex = deepNavyHex

    static let giOrange = Color(hexRGB: giOrangeHex)!
    static let royalBlue = Color(hexRGB: royalBlueHex)!
    static let energyGold = Color(hexRGB: energyGoldHex)!
    static let deepNavy = Color(hexRGB: deepNavyHex)!
    static let skyBlue = Color(hexRGB: skyBlueHex)!
    static let brandAction = giOrange
    static let energy = energyGold
    static let primaryActionForeground = Color(hexRGB: primaryActionForegroundHex)!

    static func canvasHex(for colorScheme: ColorScheme) -> String {
        colorScheme == .dark ? deepNavyHex : "#FFF8EE"
    }

    static func panelHex(for colorScheme: ColorScheme) -> String {
        colorScheme == .dark ? "#102A4C" : "#FFFFFF"
    }

    static func actionHex(for colorScheme: ColorScheme) -> String {
        colorScheme == .dark ? skyBlueHex : royalBlueHex
    }

    static func action(for colorScheme: ColorScheme) -> Color {
        Color(hexRGB: actionHex(for: colorScheme))!
    }

    static func accentForegroundHex(for colorScheme: ColorScheme) -> String {
        colorScheme == .dark ? deepNavyHex : "#FFFFFF"
    }

    static func accentForeground(for colorScheme: ColorScheme) -> Color {
        Color(hexRGB: accentForegroundHex(for: colorScheme))!
    }

    static func brandAccentHex(for colorScheme: ColorScheme) -> String {
        colorScheme == .dark ? "#FFB21C" : "#9A3F00"
    }

    static func brandAccent(for colorScheme: ColorScheme) -> Color {
        Color(hexRGB: brandAccentHex(for: colorScheme))!
    }

    static func canvas(for colorScheme: ColorScheme) -> Color {
        Color(hexRGB: canvasHex(for: colorScheme))!
    }

    static func panel(for colorScheme: ColorScheme) -> Color {
        Color(hexRGB: panelHex(for: colorScheme))!
    }

    static func raisedPanel(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? Color(hexRGB: "#16365E")! : Color(hexRGB: "#FFFDF9")!
    }

    static func navigationBarOpacity(
        for colorScheme: ColorScheme,
        reduceTransparency: Bool
    ) -> Double {
        guard !reduceTransparency else { return 1 }
        return colorScheme == .dark ? 0.86 : 0.92
    }

    static func navigationBarBackground(
        for colorScheme: ColorScheme,
        reduceTransparency: Bool
    ) -> Color {
        let base = colorScheme == .dark ? deepNavy : Color(hexRGB: "#FFF8EE")!
        return base.opacity(navigationBarOpacity(
            for: colorScheme,
            reduceTransparency: reduceTransparency
        ))
    }

    static func panelStrokeOpacity(
        for colorScheme: ColorScheme,
        increasedContrast: Bool
    ) -> Double {
        switch (colorScheme, increasedContrast) {
        case (.dark, true): 0.42
        case (.light, true): 0.32
        case (.dark, false): 0.20
        case (.light, false): 0.14
        @unknown default: increasedContrast ? 0.36 : 0.17
        }
    }

    static func subtleStroke(
        for colorScheme: ColorScheme,
        increasedContrast: Bool = false
    ) -> Color {
        let base = colorScheme == .dark ? skyBlue : royalBlue
        return base.opacity(panelStrokeOpacity(
            for: colorScheme,
            increasedContrast: increasedContrast
        ))
    }

    static var brandGradient: LinearGradient {
        LinearGradient(
            colors: [energyGold, giOrange],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static var energyGradient: LinearGradient {
        LinearGradient(
            colors: [royalBlue, skyBlue, energyGold],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    static func contrastRatio(foregroundHex: String, backgroundHex: String) -> Double {
        guard let foreground = relativeLuminance(for: foregroundHex),
              let background = relativeLuminance(for: backgroundHex)
        else { return 1 }

        let lighter = max(foreground, background)
        let darker = min(foreground, background)
        return (lighter + 0.05) / (darker + 0.05)
    }

    private static func relativeLuminance(for rawHex: String) -> Double? {
        guard let hex = HeaderLogoColor.normalizedHex(rawHex),
              let value = UInt32(String(hex.dropFirst()), radix: 16)
        else { return nil }

        let components = [
            Double((value & 0xFF0000) >> 16) / 255,
            Double((value & 0x00FF00) >> 8) / 255,
            Double(value & 0x0000FF) / 255
        ].map { component in
            component <= 0.03928
                ? component / 12.92
                : pow((component + 0.055) / 1.055, 2.4)
        }

        return (0.2126 * components[0]) + (0.7152 * components[1]) + (0.0722 * components[2])
    }
}

struct GokuBackdrop: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        ZStack {
            GokuVisualTheme.canvas(for: colorScheme)

            if !reduceTransparency {
                LinearGradient(
                    colors: colorScheme == .dark
                        ? [GokuVisualTheme.deepNavy, Color(hexRGB: "#0B2342")!, GokuVisualTheme.deepNavy]
                        : [Color(hexRGB: "#FFF8EE")!, Color(hexRGB: "#F3F7FF")!, Color(hexRGB: "#FFFDF8")!],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                RadialGradient(
                    colors: [GokuVisualTheme.giOrange.opacity(colorScheme == .dark ? 0.16 : 0.10), .clear],
                    center: .topTrailing,
                    startRadius: 4,
                    endRadius: 360
                )

                RadialGradient(
                    colors: [GokuVisualTheme.royalBlue.opacity(colorScheme == .dark ? 0.18 : 0.08), .clear],
                    center: .bottomLeading,
                    startRadius: 8,
                    endRadius: 420
                )
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct GokuAppThemeModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        content
            .tint(GokuVisualTheme.action(for: colorScheme))
            .background { GokuBackdrop().ignoresSafeArea() }
            .toolbarBackground(
                GokuVisualTheme.navigationBarBackground(
                    for: colorScheme,
                    reduceTransparency: reduceTransparency
                ),
                for: .navigationBar
            )
            .toolbarBackground(.visible, for: .navigationBar)
    }
}

private struct GokuPanelModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        content
            .background {
                shape.fill(
                    reduceTransparency
                        ? GokuVisualTheme.panel(for: colorScheme)
                        : GokuVisualTheme.panel(for: colorScheme).opacity(colorScheme == .dark ? 0.78 : 0.82)
                )
            }
            .overlay {
                shape
                    .stroke(
                        GokuVisualTheme.subtleStroke(
                            for: colorScheme,
                            increasedContrast: colorSchemeContrast == .increased
                        ),
                        lineWidth: colorSchemeContrast == .increased ? 1 : 0.8
                    )
                    .allowsHitTesting(false)
            }
            .shadow(
                color: colorScheme == .dark
                    ? GokuVisualTheme.royalBlue.opacity(0.10)
                    : GokuVisualTheme.giOrange.opacity(0.07),
                radius: 16,
                y: 7
            )
    }
}

extension View {
    func gokuAppTheme() -> some View {
        modifier(GokuAppThemeModifier())
    }

    func gokuPanel(cornerRadius: CGFloat = 18) -> some View {
        modifier(GokuPanelModifier(cornerRadius: cornerRadius))
    }
}
