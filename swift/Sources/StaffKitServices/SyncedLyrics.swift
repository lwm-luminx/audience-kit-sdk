import Foundation

/// A song's lyrics in time, for a sing-along screen: each line with when it starts, read from LRC (`[mm:ss.xx] line`),
/// the format licensed lyrics services (Musixmatch's subtitles) and karaoke libraries hand out. The screen shows the
/// line being sung, nothing else; where the lines come from is the host's business (a licensed provider, or files the
/// venue supplies), never a scrape.
public struct SyncedLyrics: Sendable, Equatable {
    public struct Line: Sendable, Equatable {
        /// Seconds into the song.
        public var time: TimeInterval
        public var text: String
        public init(time: TimeInterval, text: String) { self.time = time; self.text = text }
    }

    /// In time order. A line with no words is an instrumental break.
    public var lines: [Line]

    public init(lines: [Line]) { self.lines = lines.sorted { $0.time < $1.time } }

    /// Lyrics from LRC text: every `[mm:ss]`, `[mm:ss.xx]` or `[mm:ss:xx]` stamp on a line starts that line's words at
    /// that time (a line can carry several stamps for a repeated chorus), `[offset:±ms]` shifts them all, and the
    /// rest of the tags (`[ar:]`, `[ti:]`, …) are skipped. Nil when nothing in it is timed.
    public static func lrc(_ text: String) -> SyncedLyrics? {
        var lines: [Line] = []
        var offset: TimeInterval = 0
        for raw in text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline) {
            var rest = Substring(raw).trimmingCharacters(in: .whitespaces)[...]
            var stamps: [TimeInterval] = []
            while rest.hasPrefix("["), let close = rest.firstIndex(of: "]") {
                let tag = rest[rest.index(after: rest.startIndex)..<close]
                if let time = stamp(tag) {
                    stamps.append(time)
                } else if tag.lowercased().hasPrefix("offset:"), let ms = Double(tag.dropFirst(7).trimmingCharacters(in: .whitespaces)) {
                    // A positive offset shows the lines sooner.
                    offset = -ms / 1000
                }
                rest = rest[rest.index(after: close)...]
            }
            let words = rest.trimmingCharacters(in: .whitespaces)
            lines += stamps.map { Line(time: $0, text: words) }
        }
        guard !lines.isEmpty else { return nil }
        return SyncedLyrics(lines: lines.map { Line(time: max(0, $0.time + offset), text: $0.text) })
    }

    /// `mm:ss`, `mm:ss.xx` or `mm:ss:xx` as seconds; nil for any other tag.
    static func stamp(_ tag: Substring) -> TimeInterval? {
        let parts = tag.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2 || parts.count == 3, let minutes = Int(parts[0]), minutes >= 0 else { return nil }
        let secondsText = parts.count == 3 ? "\(parts[1]).\(parts[2])" : String(parts[1])
        guard let seconds = Double(secondsText), seconds >= 0, seconds < 60,
              secondsText.first?.isNumber == true else { return nil }
        return Double(minutes) * 60 + seconds
    }

    /// The line being sung at `position` seconds: the last that has started, or nil before the first.
    public func index(at position: TimeInterval) -> Int? {
        var low = 0, high = lines.count - 1, found: Int?
        while low <= high {
            let mid = (low + high) / 2
            if lines[mid].time <= position { found = mid; low = mid + 1 } else { high = mid - 1 }
        }
        return found
    }
}

/// Where a song is, from the player's last word on it: its position then, and whether it's playing, so a screen can
/// run the song's clock between reports.
public struct PlaybackClock: Sendable, Equatable {
    /// The song it's for (the player's track ID), so a clock never runs one song's lyrics against another.
    public var trackID: String?
    /// Seconds into the song when it was read.
    public var position: TimeInterval
    public var readAt: Date
    public var playing: Bool
    /// The song's length in seconds, when the player says.
    public var duration: TimeInterval?

    public init(trackID: String?, position: TimeInterval, readAt: Date = Date(), playing: Bool, duration: TimeInterval? = nil) {
        self.trackID = trackID; self.position = position; self.readAt = readAt; self.playing = playing
        self.duration = duration
    }

    /// Seconds into the song at `now`: still where it was when paused, else running on, never past its end.
    public func position(at now: Date) -> TimeInterval {
        guard playing else { return position }
        let running = position + max(0, now.timeIntervalSince(readAt))
        return duration.map { min(running, $0) } ?? running
    }
}
