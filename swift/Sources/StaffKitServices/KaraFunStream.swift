import Foundation

/// How Velvet Display on the Mac hands KaraFun's screen to the venue's TV apps (Rick, 2026-11-23: "the tvOS version
/// needs to receive that stream as well"). The Mac already records KaraFun's lyrics window for its own screens and
/// AirPlay; it also serves that recording as live HLS on the venue's network and announces it with Bonjour, so Velvet
/// on Apple TV (and Google TV) finds it on its own and plays it on a screen whose ranking puts KaraFun first. KaraFun's
/// sound stays on the Mac.
///
/// The announcement is a Bonjour service of `serviceType` whose TXT record carries the venue (so two venues on one
/// network don't cross), the playlist's address, and whether KaraFun has a window to show right now. The Mac records
/// only while some TV is fetching the playlist, so a TV may get a 503 for the first few seconds and should try again.
public enum KaraFunStream {
    /// The Bonjour service type (Android NSD: `_velvet-karafun._tcp.`).
    public static let serviceType = "_velvet-karafun._tcp"
    /// How long the Mac keeps recording after the last request for the stream.
    public static let idleTimeout: TimeInterval = 20

    /// The TXT record's keys.
    public enum Key {
        public static let venue = "venue"
        public static let url = "url"
        /// "1" while KaraFun is open on the Mac with a window to show, "0" otherwise.
        public static let showing = "on"
    }

    /// One Mac's announcement, as a TV reads it.
    public struct Advert: Equatable, Sendable {
        public let name: String
        public let venueID: String?
        public let url: URL?
        public let showing: Bool

        public init(name: String, venueID: String?, url: URL?, showing: Bool) {
            self.name = name
            self.venueID = venueID
            self.url = url
            self.showing = showing
        }

        /// Reads a TXT record (empty values count as missing).
        public init(name: String, txt: [String: String]) {
            func value(_ key: String) -> String? {
                guard let raw = txt[key]?.trimmingCharacters(in: .whitespaces), !raw.isEmpty else { return nil }
                return raw
            }
            self.init(name: name, venueID: value(Key.venue), url: value(Key.url).flatMap(URL.init(string:)),
                      showing: value(Key.showing) == "1")
        }

        /// The TXT record the Mac announces.
        public var txt: [String: String] {
            var record = [Key.showing: showing ? "1" : "0"]
            if let venueID { record[Key.venue] = venueID }
            if let url { record[Key.url] = url.absoluteString }
            return record
        }
    }

    /// The stream a TV signed in to `venueID` plays: a Mac of that venue showing KaraFun, else one that doesn't say its
    /// venue (signed out, or an older Mac); never another venue's. Sorted by name, so every TV picks the same Mac.
    public static func pick(_ adverts: [Advert], venueID: String?) -> Advert? {
        let showing = adverts.filter { $0.showing && $0.url != nil }.sorted { $0.name < $1.name }
        if let venueID, let own = showing.first(where: { $0.venueID == venueID }) { return own }
        return showing.first { $0.venueID == nil }
    }

    /// The playlist's address on a Mac's network.
    public static func url(host: String, port: UInt16) -> URL? {
        URL(string: "http://\(host):\(port)/live.m3u8")
    }
}
