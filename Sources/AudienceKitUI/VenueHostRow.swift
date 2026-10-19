#if canImport(SwiftUI)
import AudienceKit
import SwiftUI

/// "Up next" as a status, never a button: an outlined pill.
struct UpNextBadge: View {
    @Environment(\.audiencePreset) private var preset
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let colors = preset.colors(scheme)
        Text(String(localized: "Up next")).font(TokenFont.caption).textCase(.uppercase)
            .foregroundStyle(Color(colors.accentInk))
            .padding(.horizontal, DesignTokens.Spacing.s2).padding(.vertical, 2)
            .overlay { Capsule().strokeBorder(Color(colors.accent)) }
    }
}

/// A link on the host row: one of the host's profiles.
public struct HostLink: Identifiable, Hashable, Sendable {
    public let title: String
    public let systemImage: String
    public let url: URL
    public var id: URL { url }

    /// - Parameters:
    ///   - title: what VoiceOver says, e.g. "Trixie on Instagram".
    ///   - systemImage: an SF Symbol name.
    public init(title: String, systemImage: String, url: URL) {
        self.title = title
        self.systemImage = systemImage
        self.url = url
    }
}

/// The host on now, above ``VenueLineupStrip``: who they are, their profiles and Tip. The app supplies the links and
/// runs the tip; tips go to the host.
public struct VenueHostRow: View {
    private let host: LineupEntry
    private let links: [HostLink]
    private let onTip: (() -> Void)?
    private let onSelect: (() -> Void)?
    @Environment(\.audiencePreset) private var preset
    @Environment(\.colorScheme) private var scheme

    public init(host: LineupEntry, links: [HostLink] = [], onTip: (() -> Void)? = nil, onSelect: (() -> Void)? = nil) {
        self.host = host
        self.links = links
        self.onTip = onTip
        self.onSelect = onSelect
    }

    public var body: some View {
        let colors = preset.colors(scheme)
        HStack(spacing: DesignTokens.Spacing.s3) {
            Button { onSelect?() } label: {
                HStack(spacing: DesignTokens.Spacing.s3) {
                    Avatars(entry: host, size: 48)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(host.displayName).font(TokenFont.subheading).foregroundStyle(Color(colors.ink))
                        Text(String(localized: "Your host tonight")).font(TokenFont.bodySm)
                            .foregroundStyle(Color(colors.inkMuted))
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain).disabled(onSelect == nil)
            Spacer(minLength: 0)
            ForEach(links) { link in
                Link(destination: link.url) { Image(systemName: link.systemImage).frame(width: 44, height: 44) }
                    .foregroundStyle(Color(colors.inkMuted)).accessibilityLabel(link.title)
            }
            if let onTip {
                Button(action: onTip) {
                    Text(String(localized: "Tip")).font(TokenFont.label).foregroundStyle(Color(colors.onAccent))
                        .padding(.horizontal, 14).frame(minHeight: 36).background(Color(colors.accent), in: Capsule())
                }
                .buttonStyle(.plain).accessibilityLabel(String(localized: "Tip \(host.displayName)"))
            }
        }
        .padding(DesignTokens.Spacing.s3)
        .background(Color(colors.surfaceRaised), in: RoundedRectangle(cornerRadius: 16))
        .overlay { RoundedRectangle(cornerRadius: 16).strokeBorder(Color(colors.border)) }
        .padding(.horizontal, DesignTokens.Spacing.s4)
    }
}
#endif
