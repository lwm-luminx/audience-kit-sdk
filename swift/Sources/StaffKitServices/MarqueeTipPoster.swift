import Foundation

/// A full-screen tip poster on the venue's screens: one of tonight's hosts or performers who takes tips by link, with
/// their photo and a big code for each link (Rick, 2026-11-23: "we should build poster screens with tipping info").
/// They take turns in the board's breaks and the posters screen, in place of the small tip codes the Tonight page
/// had (Rick, 2026-11-23: "lets drop the tip QR codes from the main page in favor of the poster screens"). The
/// printable one is the console's Tip poster (audience_kit_api components/Poster/tip.ts), the same layout on paper.
public struct MarqueeTipPoster: Sendable, Equatable, Identifiable {
    /// One way to tip them.
    public struct Link: Sendable, Equatable {
        /// "Cash App", "Venmo".
        public let provider: String
        /// The handle as fans type it: "$daltonkj", "@daltonkj"; empty when the API has none.
        public let handle: String
        /// What the code opens.
        public let url: String
    }

    public let id: String
    public let name: String
    public let photo: String?
    public let links: [Link]

    /// How many people take turns, hosts first; more than this and the loop is mostly tips.
    public static let limit = 6
    /// Codes on one poster, side by side.
    public static let linksPerPoster = 3

    /// Tonight's hosts, then the KJ, DJ or VJ, then performers, once each, who have a tip link, at most `limit`.
    /// A jockey is billed with their title: "KJ Dalton".
    public static func tonight(_ events: [VenueEvent]) -> [MarqueeTipPoster] {
        var seen = Set<String>()
        let live = events.filter { !$0.isCanceled }
        func billed(_ person: VenueEvent.Person) -> String {
            live.lazy.compactMap { $0.jockeys.contains { $0.id == person.id } ? $0.billedName(person) : nil }.first
                ?? person.name ?? "the performer"
        }
        return live.flatMap { $0.hosts + $0.jockeys + $0.people }
            .filter { !$0.tipLinks.isEmpty && seen.insert($0.id).inserted }
            .prefix(limit)
            .map { person in
                MarqueeTipPoster(
                    id: person.id, name: billed(person), photo: person.avatarUrl,
                    links: person.tipLinks.prefix(linksPerPoster).map {
                        Link(provider: $0.name, handle: handle($0), url: $0.url ?? "")
                    })
            }
    }

    /// "$handle" for Cash App, "@handle" for Venmo, the handle as given otherwise.
    static func handle(_ link: VenueEvent.Person.TipLink) -> String {
        var bare = (link.handle ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        while bare.hasPrefix("$") || bare.hasPrefix("@") { bare.removeFirst() }
        guard !bare.isEmpty else { return "" }
        let lower = link.name.lowercased()
        return lower.contains("cash") ? "$\(bare)" : lower.contains("venmo") ? "@\(bare)" : bare
    }
}

extension VenueWorkspace {
    /// Tonight's tip posters (`MarqueeTipPoster.tonight`).
    public var tipPosters: [MarqueeTipPoster] { MarqueeTipPoster.tonight(events.filter(isTonight)) }
}
