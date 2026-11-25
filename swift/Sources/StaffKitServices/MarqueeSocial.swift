import Foundation

/// One of the venue's social media profiles on its screens' "follow us" slide, which comes round once after every
/// round of event posters in the poster loop (or in their place when there are none).
public struct MarqueeSocialProfile: Sendable, Equatable, Identifiable {
    public let provider: String
    /// The network's name, "Instagram".
    public let network: String
    /// The handle as people search for it, "@kremwerk".
    public let handle: String
    /// The profile, https only, for the QR code.
    public let url: String

    public var id: String { provider }
}

/// Which of a venue's social links its screens show, and how: known social networks only (never tip links like Cash App
/// or Venmo), https profile links, one per network, in `order`, at most `limit`. The web sign and the cast receiver
/// (hotmess.social `src/lib/poster/social.ts`) keep the same ones.
public enum MarqueeSocial {
    /// The networks shown, in order, with their names.
    public static let order: [(provider: String, network: String)] = [
        ("instagram", "Instagram"), ("tiktok", "TikTok"), ("facebook", "Facebook"), ("x", "X"), ("threads", "Threads"),
        ("bluesky", "Bluesky"), ("youtube", "YouTube"), ("linktree", "Linktree"), ("discord", "Discord"),
    ]
    /// How many the slide shows, each with its own code.
    public static let limit = 4
    /// Networks whose handles people type with an @.
    private static let at: Set<String> = ["instagram", "tiktok", "x", "threads", "bluesky"]

    /// The handle as people look for it: "@kiki", "linktr.ee/kiki", "discord.gg/abc".
    public static func displayHandle(provider: String, handle: String) -> String {
        var bare = handle.trimmingCharacters(in: .whitespacesAndNewlines)
        while bare.hasPrefix("@") { bare.removeFirst() }
        guard !bare.isEmpty else { return "" }
        switch provider {
        case _ where at.contains(provider): return "@\(bare)"
        case "youtube": return bare.contains("/") ? bare : "@\(bare)"
        case "linktree": return "linktr.ee/\(bare)"
        case "discord": return "discord.gg/\(bare)"
        default: return bare
        }
    }

    /// The profiles to show from the venue's links.
    public static func profiles(_ links: [VenueWorkspace.SocialLink]) -> [MarqueeSocialProfile] {
        var found: [String: MarqueeSocialProfile] = [:]
        for link in links {
            let given = link.provider.lowercased()
            let provider = given == "twitter" ? "x" : given
            guard found[provider] == nil, let network = order.first(where: { $0.provider == provider })?.network,
                  let url = link.url, url.hasPrefix("https://") else { continue }
            let handle = displayHandle(provider: provider, handle: link.handle)
            guard !handle.isEmpty else { continue }
            found[provider] = MarqueeSocialProfile(provider: provider, network: network, handle: handle, url: url)
        }
        return Array(order.compactMap { found[$0.provider] }.prefix(limit))
    }

    /// The profiles for a cast receiver's `social` (it cleans them again).
    public static func castProfiles(_ profiles: [MarqueeSocialProfile]) -> [[String: Any]] {
        profiles.map { ["provider": $0.provider, "handle": $0.handle, "url": $0.url] }
    }
}

extension VenueWorkspace {
    /// Its social profiles for its screens' follow-us slide (`MarqueeSocial`).
    public var socialProfiles: [MarqueeSocialProfile] { MarqueeSocial.profiles(socialLinks ?? []) }
}
