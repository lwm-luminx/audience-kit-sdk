#if canImport(SwiftUI)
import AudienceKit
import SwiftUI

extension SocialLink {
    /// The button's title for a community chat: "Join on Discord", "Join on Matrix", "Join on IRC", "Mailing list".
    public var joinTitle: String { provider == "mailing_list" ? "Mailing list" : "Join on \(networkName)" }

    /// An SF Symbol for its network.
    public var systemImage: String {
        switch provider {
        case "discord", "matrix": "bubble.left.and.bubble.right"
        case "irc": "number"
        case "mailing_list": "envelope"
        default: "link"
        }
    }
}

/// Join buttons for a venue's or event's community chats elsewhere (``SocialLink/isCommunityChat``): its Discord
/// server, Matrix room, IRC channel or mailing list, each opening its link. Shows nothing when there are none.
///
/// ```swift
/// CommunityChatLinks(event.communityChats)
/// CommunityChatLinks(venueDetail.communityChats)
/// ```
public struct CommunityChatLinks<Label: View>: View {
    private let links: [SocialLink]
    private let label: (SocialLink) -> Label
    @Environment(\.openURL) private var openURL

    /// - Parameters:
    ///   - links: the links to offer; anything that isn't a community chat, or has no URL, is left out.
    ///   - label: draws one link's button, e.g. from ``SocialLink/joinTitle`` and ``SocialLink/systemImage``.
    public init(_ links: [SocialLink], @ViewBuilder label: @escaping (SocialLink) -> Label) {
        self.links = links.filter { $0.isCommunityChat && $0.link != nil }
        self.label = label
    }

    public var body: some View {
        ForEach(links) { link in
            Button {
                if let url = link.link { openURL(url) }
            } label: {
                label(link)
            }
            .accessibilityIdentifier("communityChat.\(link.provider)")
        }
    }
}

extension CommunityChatLinks where Label == SwiftUI.Label<Text, Image> {
    /// The plain buttons: "Join on Discord" with a chat bubble, and so on.
    public init(_ links: [SocialLink]) {
        self.init(links) { link in SwiftUI.Label(link.joinTitle, systemImage: link.systemImage) }
    }
}
#endif
