import Foundation
import AudienceCore

/// One entry of the `socialLinks` list PersonInput and VenueInput take (`SocialLinkInput`): a provider and a handle,
/// or a profile link, there. The list replaces the record's links wholesale, so a client sends the links it leaves
/// alone along with the ones it changes: see `replacing(_:with:)`.
public struct SocialLinkInput: Sendable, Hashable {
    /// instagram, tiktok, facebook, x, threads, bluesky, youtube, linktree; soundcloud, spotify or apple_music for
    /// music; cashapp or venmo for tips.
    public let provider: String
    /// The handle there, or a link to the profile.
    public let handle: String

    public init(provider: String, handle: String) {
        self.provider = provider
        self.handle = handle
    }

    /// The `SocialLinkInput` the API's mutations take.
    public var graphQLValue: GraphQLValue { .object(["provider": .string(provider), "handle": .string(handle)]) }

    /// Hosts and the provider whose profiles live there, as the API knows them.
    static let hosts: [String: String] = [
        "instagram.com": "instagram", "facebook.com": "facebook", "fb.com": "facebook", "tiktok.com": "tiktok",
        "x.com": "x", "twitter.com": "x", "threads.net": "threads", "threads.com": "threads", "bsky.app": "bluesky",
        "youtube.com": "youtube", "soundcloud.com": "soundcloud", "open.spotify.com": "spotify",
        "podcasts.apple.com": "apple_podcasts", "music.apple.com": "apple_music", "linktr.ee": "linktree", "cash.app": "cashapp", "venmo.com": "venmo"
    ]

    /// The provider a profile link is on, by its host (`open.spotify.com/artist/1` is spotify). A link on a host the
    /// API doesn't know gives that host's name (`bandcamp` for bandcamp.com), so the API's answer names it; a bare
    /// handle gives nil.
    public static func provider(ofLink link: String) -> String? {
        let value = link.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.contains("/") || value.contains(".") else { return nil }
        let address = value.range(of: "^[a-z][a-z0-9+.-]*://", options: [.regularExpression, .caseInsensitive]) == nil ? "https://\(value)" : value
        guard var host = URLComponents(string: address)?.host?.lowercased(), !host.isEmpty else { return nil }
        for prefix in ["www.", "m."] where host.hasPrefix(prefix) { host.removeFirst(prefix.count) }
        if let provider = hosts[host] { return provider }
        let labels = host.split(separator: ".").map(String.init)
        if labels.count > 2, let provider = hosts[labels.suffix(2).joined(separator: ".")] { return provider }
        return labels.count > 1 ? labels[labels.count - 2] : labels.first
    }

    /// The whole list to send: `current` (the record's links, as provider and handle) on networks `edits` leaves
    /// alone, then `edits` (provider => handles or links typed; blank ones remove the provider's links).
    public static func replacing(_ current: [(provider: String, handle: String)], with edits: [String: [String]]) -> [SocialLinkInput] {
        let kept = current.filter { edits[$0.provider] == nil }.map { SocialLinkInput(provider: $0.provider, handle: $0.handle) }
        let edited = edits.keys.sorted().flatMap { provider in
            (edits[provider] ?? []).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
                .map { SocialLinkInput(provider: provider, handle: $0) }
        }
        var seen = Set<SocialLinkInput>()
        return (kept + edited).filter { seen.insert($0).inserted }
    }

    /// `edits` for links typed as addresses (music links), grouped by the provider each is on. `providers` are the
    /// ones the field stands for, so leaving all their links out removes them.
    public static func grouped(links: [String], providers: [String]) -> [String: [String]] {
        var edits = Dictionary(uniqueKeysWithValues: providers.map { ($0, [String]()) })
        for link in links.map({ $0.trimmingCharacters(in: .whitespacesAndNewlines) }) where !link.isEmpty {
            edits[provider(ofLink: link) ?? "link", default: []].append(link)
        }
        return edits
    }
}
