import Foundation
import StaffKitCore

/// The photo wall screen: the venue's trusted photographers' recent photos. Trusted means the photographers the
/// audience connected (the Photography module's professional photos, still under an active grant), never members'
/// crowd photos, and never one a manager hid or someone reported.
///
/// A screen ranks its types and falls through to the next when one has nothing to show, so `hasContent` says whether
/// the wall has anything: only photos taken in the last `recentDays` count, so a venue whose photographers stopped
/// coming doesn't keep last year's nights on its TV.
public struct MarqueePhotoWall: Sendable, Equatable {
    /// How many of the venue's newest photos the screen reads.
    public static let limit = 40
    /// How long a list is used before it's read again.
    public static let refresh: TimeInterval = 600
    /// How far back a photo still counts as recent.
    public static let recentDays = 90
    /// How many photos the wall shows at once: one large and the rest beside it.
    public static let tiles = 5

    /// The photos to show, newest first.
    public let photos: [VenueEventPhoto]

    /// The wall from the photos the API gave (newest first): the visible, recent ones with an https preview.
    public init(_ photos: [VenueEventPhoto], now: Date = Date(), recentDays: Int = MarqueePhotoWall.recentDays) {
        let since = now.addingTimeInterval(-Double(recentDays) * 86_400)
        var seen = Set<String>()
        self.photos = photos.filter { photo in
            guard !photo.isHidden, photo.url.hasPrefix("https://"), seen.insert(photo.url).inserted else { return false }
            // Undated photos can't be shown to be recent, so they're left out.
            guard let taken = parseInstant(photo.takenAt) else { return false }
            return taken >= since && taken <= now.addingTimeInterval(86_400)
        }
    }

    /// Whether the wall has anything to show; when it doesn't, the screen moves on to its next type.
    public var hasContent: Bool { !photos.isEmpty }

    /// The photos on the wall when `start` leads: it large, then the ones after it, round again, at most `tiles`.
    public func showing(from start: Int, tiles: Int = MarqueePhotoWall.tiles) -> [VenueEventPhoto] {
        guard !photos.isEmpty else { return [] }
        let count = min(tiles, photos.count)
        return (0..<count).map { photos[(start + $0) % photos.count] }
    }

    /// The photographers to credit, each once, in the order their photos come.
    public static func credits(_ photos: [VenueEventPhoto]) -> [String] {
        var seen = Set<String>()
        return photos.map(\.photographer.name).filter { !$0.isEmpty && seen.insert($0.lowercased()).inserted }
    }

    /// The credit line: "Photos by Ana" / "Photos by Ana and Bo" / "Photos by Ana, Bo and 2 more".
    public static func creditLine(_ photos: [VenueEventPhoto]) -> String? {
        let names = credits(photos)
        switch names.count {
        case 0: return nil
        case 1: return "Photos by \(names[0])"
        case 2: return "Photos by \(names[0]) and \(names[1])"
        case 3: return "Photos by \(names[0]), \(names[1]) and \(names[2])"
        default: return "Photos by \(names[0]), \(names[1]) and \(names.count - 2) more"
        }
    }

    /// What one photo says under it: its caption, else its event's name.
    public static func words(_ photo: VenueEventPhoto) -> String? {
        if let caption = photo.caption?.trimmingCharacters(in: .whitespacesAndNewlines), !caption.isEmpty { return caption }
        if let name = photo.event?.name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty { return name }
        return nil
    }

    /// The wall for a cast receiver (hotmess.social `/cast/velvet`, mode "photos"): each photo's preview, words and
    /// credit, at most `max`. Empty when there's nothing, so the TV falls back as it does for any mode it can't fill.
    public func castPhotos(max: Int = 24) -> [[String: Any]] {
        photos.prefix(max).map { photo in
            var row: [String: Any] = ["id": photo.id, "url": photo.url, "credit": photo.photographer.name]
            if let words = Self.words(photo) { row["caption"] = words }
            if let alt = photo.altText, !alt.isEmpty { row["alt"] = alt }
            if let width = photo.width, let height = photo.height, width > 0, height > 0 {
                row["width"] = width
                row["height"] = height
            }
            return row
        }
    }
}

extension VenueManagementClient {
    /// The venue's photo wall, read fresh; empty when the audience has no photographers or the read fails.
    public func photoWall(venueID: String, now: Date = Date()) async -> MarqueePhotoWall {
        let photos = (try? await photos(of: .venue(id: venueID), first: MarqueePhotoWall.limit)) ?? []
        return MarqueePhotoWall(photos, now: now)
    }
}
