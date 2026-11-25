import Foundation

/// How a Velvet TV app announces itself on the venue's network (Rick, 2026-11-25: "add into velvet tvOS and android TV
/// our own bonjour advertisement"). Velvet on Apple TV and Google TV each publish a Bonjour service of `serviceType`
/// whose TXT record says which install it is, which display record it shows and which venue it's paired to, so the
/// Velvet helper on the venue's Mac finds our own TV apps directly and keeps them on the same screen record as that
/// TV's AirPlay and Chromecast adverts (it keys a screen on `display`, else `device`, and matches the rest by host).
///
/// The TV listens on a TCP port only so the service resolves to its address; it speaks no protocol there and closes
/// every connection. Every key but `Key.version` is optional: a signed-out TV has no venue or display. The TV
/// re-announces whenever a value changes. The Mac helper compiles this file in directly, so it imports only Foundation.
public enum VelvetScreenAdvert {
    /// The Bonjour service type (Android NSD: `_velvet._tcp.`).
    public static let serviceType = "_velvet._tcp"
    /// The TXT record's schema version.
    public static let version = "1"

    /// The TXT record's keys.
    public enum Key {
        public static let version = "v"
        /// "tvos" or "androidtv": the platform the TV sends when it pairs (POST /v1/venue-devices/pairings).
        public static let platform = "platform"
        /// The install's permanent identifier: the one the TV sends as `identifier` when it pairs or redeems a code.
        public static let device = "device"
        /// The TV's venue display record (registerVenueDisplay).
        public static let display = "display"
        public static let venue = "venue"
        public static let audience = "audience"
        /// The app's version (CFBundleShortVersionString, Android versionName) and build number.
        public static let app = "app"
        public static let build = "build"
        /// The hardware model, e.g. "AppleTV14,1" or Android's Build.MODEL.
        public static let model = "model"
    }

    /// One TV's announcement.
    public struct Advert: Equatable, Sendable {
        public var name: String
        public var platform: String?
        public var deviceID: String?
        public var displayID: String?
        public var venueID: String?
        public var audienceID: String?
        public var appVersion: String?
        public var build: String?
        public var model: String?

        public init(name: String, platform: String? = nil, deviceID: String? = nil, displayID: String? = nil,
                    venueID: String? = nil, audienceID: String? = nil, appVersion: String? = nil,
                    build: String? = nil, model: String? = nil) {
            self.name = name
            self.platform = platform
            self.deviceID = deviceID
            self.displayID = displayID
            self.venueID = venueID
            self.audienceID = audienceID
            self.appVersion = appVersion
            self.build = build
            self.model = model
        }

        /// Reads a TXT record (empty values count as missing).
        public init(name: String, txt: [String: String]) {
            func value(_ key: String) -> String? {
                guard let raw = txt[key]?.trimmingCharacters(in: .whitespaces), !raw.isEmpty else { return nil }
                return raw
            }
            self.init(name: name, platform: value(Key.platform), deviceID: value(Key.device),
                      displayID: value(Key.display), venueID: value(Key.venue), audienceID: value(Key.audience),
                      appVersion: value(Key.app), build: value(Key.build), model: value(Key.model))
        }

        /// The key the Mac helper files this screen under: its display record, else its install.
        public var screenKey: String? { displayID ?? deviceID }

        /// The TXT record the TV announces. Each value is cut to fit one TXT string (255 bytes with "key=").
        public var txt: [String: String] {
            var record = [Key.version: VelvetScreenAdvert.version]
            let values: [(String, String?)] = [
                (Key.platform, platform), (Key.device, deviceID), (Key.display, displayID), (Key.venue, venueID),
                (Key.audience, audienceID), (Key.app, appVersion), (Key.build, build), (Key.model, model),
            ]
            for (key, value) in values {
                guard let value = value?.trimmingCharacters(in: .whitespaces), !value.isEmpty else { continue }
                record[key] = VelvetScreenAdvert.prefix(value, bytes: 254 - key.utf8.count)
            }
            return record
        }
    }

    /// The service's instance name: the TV's own name, cut to a DNS label's 63 bytes.
    public static func instanceName(_ deviceName: String) -> String {
        let trimmed = deviceName.trimmingCharacters(in: .whitespacesAndNewlines)
        return prefix(trimmed.isEmpty ? "Velvet TV" : trimmed, bytes: 63)
    }

    /// The longest prefix of `value` that fits in `bytes` of UTF-8 without splitting a character.
    static func prefix(_ value: String, bytes: Int) -> String {
        var result = "", used = 0
        for character in value {
            let size = String(character).utf8.count
            guard used + size <= bytes else { break }
            result.append(character)
            used += size
        }
        return result
    }
}
