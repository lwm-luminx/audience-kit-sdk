import Foundation

/// Where the faces are in a photo (the API's PhotoFocus, `faces` and `focalPoint` on a photo or banner image), so a
/// crop keeps them: a 1080-square Instagram post shown 16:9 behind Velvet's board, a poster, a card (Rick,
/// 2026-11-21). Everything is a fraction of the upright image, 0...1 from its top left.
public struct PhotoFocus: Decodable, Sendable, Equatable {
    public struct Point: Decodable, Sendable, Equatable {
        public let x: Double
        public let y: Double
        public init(x: Double, y: Double) { self.x = x; self.y = y }
    }
    public struct Face: Decodable, Sendable, Equatable {
        public let x: Double
        public let y: Double
        public let width: Double
        public let height: Double
        public init(x: Double, y: Double, width: Double, height: Double) {
            self.x = x; self.y = y; self.width = width; self.height = height
        }
    }

    public let focalPoint: Point?
    public let faces: [Face]

    public init(focalPoint: Point?, faces: [Face] = []) {
        self.focalPoint = focalPoint
        self.faces = faces
    }

    enum CodingKeys: String, CodingKey { case focalPoint, faces }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        focalPoint = try container.decodeIfPresent(Point.self, forKey: .focalPoint)
        faces = try container.decodeIfPresent([Face].self, forKey: .faces) ?? []
    }

    /// A photo link without its query, so a focus read once still matches the same photo's link signed for another
    /// week (`?sig=`).
    public static func key(_ url: String) -> String {
        url.split(separator: "?", maxSplits: 1).first.map(String.init) ?? url
    }

    /// The largest window of `aspect` (width / height) in a `width` × `height` image that keeps every face in frame
    /// when they fit together, else the largest face, else centres on the focal point (the middle without one).
    /// Returns (x, y, width, height) in pixels. The API's PhotoFocus.crop is the same rule.
    public func crop(width: Double, height: Double, aspect: Double) -> (x: Double, y: Double, width: Double, height: Double) {
        guard width > 0, height > 0, aspect > 0 else { return (0, 0, width, height) }
        let (cropW, cropH) = width / height > aspect ? (height * aspect, height) : (width, width / aspect)
        var centerX = (focalPoint?.x ?? 0.5) * width
        var centerY = (focalPoint?.y ?? 0.5) * height
        let boxes = faces.map { (x: $0.x * width, y: $0.y * height, w: $0.width * width, h: $0.height * height) }
        if let left = boxes.map(\.x).min(), let top = boxes.map(\.y).min(),
           let right = boxes.map({ $0.x + $0.w }).max(), let bottom = boxes.map({ $0.y + $0.h }).max() {
            if right - left <= cropW, bottom - top <= cropH {
                centerX = (left + right) / 2
                centerY = (top + bottom) / 2
            } else if let largest = boxes.max(by: { $0.w * $0.h < $1.w * $1.h }) {
                centerX = largest.x + largest.w / 2
                centerY = largest.y + largest.h / 2
            }
        }
        let x = min(max(centerX - cropW / 2, 0), width - cropW)
        let y = min(max(centerY - cropH / 2, 0), height - cropH)
        return (x.rounded(), y.rounded(), cropW.rounded(), cropH.rounded())
    }
}

extension Array where Element == ScreenBackdrop {
    /// The picture behind a slide with type over it (the follow-us slide, an event poster without its own banner):
    /// the venue's own Instagram posts first, then its other pictures, never one that's mostly text.
    public var slideBackdrop: ScreenBackdrop? {
        first { $0.source == "instagram" && $0.hasText != true } ?? first { $0.hasText != true }
    }
}

/// A picture Velvet's screens may show behind the board (`Venue.screenBackdrops`), with where its faces are.
public struct ScreenBackdrop: Decodable, Sendable, Equatable {
    public let url: String
    /// "banner", "instagram" or "google".
    public let source: String
    /// Whether it's mostly text (a flyer); nil before the API has looked. The API already puts these last.
    public let hasText: Bool?
    public let focus: PhotoFocus

    public init(url: String, source: String, hasText: Bool? = nil, focus: PhotoFocus = PhotoFocus(focalPoint: nil)) {
        self.url = url; self.source = source; self.hasText = hasText; self.focus = focus
    }

    enum CodingKeys: String, CodingKey { case url, source, hasText }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        url = try container.decode(String.self, forKey: .url)
        source = try container.decode(String.self, forKey: .source)
        hasText = try container.decodeIfPresent(Bool.self, forKey: .hasText)
        focus = try PhotoFocus(from: decoder)
    }
}
