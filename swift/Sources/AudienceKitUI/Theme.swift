#if canImport(SwiftUI)
import AudienceCore
import SwiftUI

extension Color {
    /// A design token's colour.
    public init(_ color: RGBAColor) {
        self.init(.sRGB, red: color.red, green: color.green, blue: color.blue, opacity: color.alpha)
    }
}

private struct AudiencePresetKey: EnvironmentKey {
    static let defaultValue = DesignTokens.presets["default"]!
}

extension EnvironmentValues {
    /// The theme AudienceKitUI's views draw with: an audience's preset (`AudienceTheme.preset`), light and dark.
    public var audiencePreset: DesignTokens.Preset {
        get { self[AudiencePresetKey.self] }
        set { self[AudiencePresetKey.self] = newValue }
    }
}

extension View {
    /// Draws AudienceKitUI's views inside with an audience's preset, by the key `AudienceTheme.preset` stores
    /// ("default", "hot_mess"); an unknown key keeps the default.
    public func audiencePreset(_ key: String) -> some View {
        environment(\.audiencePreset, DesignTokens.presets[key] ?? DesignTokens.presets["default"]!)
    }
}

extension DesignTokens.Preset {
    /// Its colours for a colour scheme.
    func colors(_ scheme: ColorScheme) -> DesignTokens.Colors { scheme == .dark ? dark : light }
}

extension DesignTokens.TypeStyle {
    /// The style as a font that grows with Dynamic Type from the text style it stands in for. Its family when the
    /// app bundles it, else the system font.
    func font(relativeTo textStyle: Font.TextStyle) -> Font {
        .custom(fontFamily, size: fontSize, relativeTo: textStyle).weight(weight)
    }

    private var weight: Font.Weight {
        switch fontWeight {
        case ..<450: .regular
        case ..<550: .medium
        case ..<650: .semibold
        case ..<750: .bold
        default: .heavy
        }
    }
}

/// The token type scale, mapped to the text styles Dynamic Type scales.
enum TokenFont {
    static var heading: Font { DesignTokens.Typography.heading.font(relativeTo: .headline) }
    static var subheading: Font { DesignTokens.Typography.subheading.font(relativeTo: .body) }
    static var body: Font { DesignTokens.Typography.body.font(relativeTo: .body) }
    static var bodySm: Font { DesignTokens.Typography.bodySm.font(relativeTo: .footnote) }
    static var label: Font { DesignTokens.Typography.label.font(relativeTo: .body) }
    static var caption: Font { DesignTokens.Typography.caption.font(relativeTo: .caption) }
}
#endif
