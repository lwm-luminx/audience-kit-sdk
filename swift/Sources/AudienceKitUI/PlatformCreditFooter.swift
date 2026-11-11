#if canImport(SwiftUI)
import AudienceKit
import SwiftUI

/// "Powered by AudienceKit · A Love Wins Media product" for the foot of an app's About or Settings screen, with
/// Love Wins Media in the pink-to-amber gradient and each name linking to its site, then AudienceKit's policy links
/// (Privacy · Terms · Child safety · Contact), "Bring AudienceKit to your venue" and the copyright line. Words, links
/// and colours come from ``PlatformCredit``.
///
/// ```swift
/// List {
///     …
///     Section { } footer: { PlatformCreditFooter() }
/// }
/// ```
public struct PlatformCreditFooter: View {
    private let showsPolicies: Bool
    private let showsCallToAction: Bool
    private let showsCopyright: Bool
    @Environment(\.colorScheme) private var scheme

    /// - Parameters:
    ///   - showsPolicies: AudienceKit's Privacy, Terms, Child safety and Contact links.
    ///   - showsCallToAction: "Bring AudienceKit to your venue"; staff apps already used by a venue can leave it out.
    ///   - showsCopyright: "© <year> Love Wins Media, Inc." underneath.
    public init(showsPolicies: Bool = true, showsCallToAction: Bool = true, showsCopyright: Bool = true) {
        self.showsPolicies = showsPolicies
        self.showsCallToAction = showsCallToAction
        self.showsCopyright = showsCopyright
    }

    public var body: some View {
        VStack(spacing: 4) {
            VStack(spacing: 4) {
                HStack(spacing: 0) {
                    Text(PlatformCredit.poweredByPrefix)
                        .foregroundStyle(.secondary)
                    Link(destination: PlatformCredit.platformURL()) {
                        Text(PlatformCredit.platformName)
                            .fontWeight(.semibold)
                            .foregroundStyle(.primary)
                    }
                }
                HStack(spacing: 0) {
                    Text(PlatformCredit.productPrefix)
                        .foregroundStyle(.secondary)
                    Link(destination: PlatformCredit.companyURL()) {
                        Text(PlatformCredit.companyName)
                            .fontWeight(.semibold)
                            .foregroundStyle(gradient)
                    }
                    Text(PlatformCredit.productSuffix)
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(PlatformCredit.spoken)
            .accessibilityAddTraits(.isLink)

            if showsPolicies {
                HStack(spacing: 6) {
                    ForEach(Array(PlatformCredit.policies.enumerated()), id: \.offset) { index, policy in
                        if index > 0 {
                            Text("·").foregroundStyle(.tertiary).accessibilityHidden(true)
                        }
                        Link(policy.title, destination: PlatformCredit.policyURL(policy))
                            .foregroundStyle(.secondary)
                    }
                }
                .font(.caption)
                .padding(.top, 4)
                .accessibilityIdentifier("platformCredit.policies")
            }

            if showsCallToAction {
                Link(destination: PlatformCredit.callToActionURL()) {
                    HStack(spacing: 4) {
                        Text(PlatformCredit.callToAction)
                        Image(systemName: "arrow.up.forward").imageScale(.small).accessibilityHidden(true)
                    }
                    .font(.footnote.weight(.semibold))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .foregroundStyle(gradient)
                    .background(Capsule().strokeBorder(gradient, lineWidth: 1))
                }
                .padding(.top, 6)
                .accessibilityIdentifier("platformCredit.callToAction")
            }

            if showsCopyright {
                Text(PlatformCredit.copyright())
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .padding(.top, 2)
            }
        }
        .font(.footnote)
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .textCase(nil)
        .accessibilityIdentifier("platformCredit")
    }

    private var gradient: LinearGradient {
        let stops = (scheme == .dark ? PlatformCredit.gradientDark : PlatformCredit.gradientLight)
            .map(Color.init(platformCreditHex:))
        return LinearGradient(colors: stops, startPoint: .leading, endPoint: .trailing)
    }
}

extension Color {
    /// "#rrggbb" to a colour (sRGB); anything else is clear.
    init(platformCreditHex hex: String) {
        let digits = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        guard digits.count == 6, let value = UInt32(digits, radix: 16) else {
            self = .clear
            return
        }
        self.init(.sRGB,
                  red: Double((value >> 16) & 0xFF) / 255,
                  green: Double((value >> 8) & 0xFF) / 255,
                  blue: Double(value & 0xFF) / 255)
    }
}

#if DEBUG
#Preview("Platform credit") {
    List {
        Section("About") { LabeledContent("Version", value: "1.0 (1)") }
        Section { } footer: { PlatformCreditFooter() }
    }
}
#endif
#endif
