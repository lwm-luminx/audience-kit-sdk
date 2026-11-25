import Foundation

/// A made-up live activity for UI tests and App Store screenshots (Rick, 2026-11-22: "running a synthetic sing along /
/// bingo game"): a bingo game whose host calls a number every few seconds, or a sing-along whose lyrics run from the
/// moment it starts. Debug builds launched with `AK_UI_TEST_ACTIVITY=bingo` or `sing_along` get it from
/// `venueGames(venueID:)` instead of the venue's own, so every screen that follows the live activity shows it with
/// nothing running at the venue; `none` stands for a venue with nothing set, whatever is running there for real (the
/// demo venue may have a game going). Release builds never read the variable.
///
/// The sing-along's song and words are written for this demo; they're not anyone's lyrics.
public enum SyntheticActivity {
    /// The variable a UI test sets on the app's launch environment.
    public static let environmentKey = "AK_UI_TEST_ACTIVITY"
    /// When the demo started: the bingo host's first call and the song's first beat.
    public static let started = Date()

    /// The activity the launch environment asks for, if any. Only Debug builds look.
    public static var requested: String? {
        #if DEBUG
        let value = ProcessInfo.processInfo.environment[environmentKey]
        return value?.isEmpty == false ? value : nil
        #else
        return nil
        #endif
    }

    /// What the screens show for `kind` (`bingo`, `sing_along`, or `none` for nothing set) at `now`; nil for any other
    /// kind.
    public static func games(_ kind: String, now: Date = Date(), started: Date = started) -> VenueGames? {
        switch kind {
        case "none":
            return VenueGames(followsActivity: true)
        case "bingo":
            return VenueGames(bingo: bingo(now: now, started: started),
                              activity: VenueLiveActivity(kind: VenueLiveActivity.bingo), followsActivity: true)
        case "sing_along":
            let song = singAlong(started: started)
            return VenueGames(activity: VenueLiveActivity(kind: VenueLiveActivity.singAlong, song: song),
                              followsActivity: true)
        default:
            return nil
        }
    }

    /// The order the demo host draws the balls in: spread over the board so every column lights up.
    static let draws = [7, 22, 41, 53, 68, 12, 30, 45, 61, 3, 19, 37, 50, 72, 26, 9, 58, 33, 66, 44, 15, 70, 28, 55, 1,
                        39, 63, 18, 47, 74, 11, 34, 60, 24, 52, 5, 42, 69, 31, 57]

    /// Twelve balls already out when the screen comes up, then one more every four seconds, up to forty.
    static func bingo(now: Date, started: Date) -> StaffBingoGame {
        let count = min(draws.count, 12 + max(0, Int(now.timeIntervalSince(started) / 4)))
        let letters = ["B", "I", "N", "G", "O"]
        let calls = draws.prefix(count).map { number in
            let letter = letters[(number - 1) / 15]
            return BingoCall(number: number, letter: letter)
        }
        return StaffBingoGame(id: "synthetic-bingo", pattern: "Four corners", calls: calls,
                              startedAt: ISO8601DateFormatter().string(from: started))
    }

    /// "Velvet Rope", by the demo's house band: a line every four seconds, from three seconds before the screen came up
    /// so the first line is already being sung.
    static func singAlong(started: Date) -> LiveSong {
        let words = [
            "Doors at nine, the line's around the block",
            "Glitter on the sidewalk, hands up on the clock",
            "Velvet rope, let us in tonight",
            "Every face a friend beneath the light",
            "DJ, turn it up and let the bass go low",
            "Everybody sing it, here we go",
            "Velvet rope, we're dancing till it's done",
            "Last call never comes when we're all one",
        ]
        let lines = (words + words).enumerated().map { LiveSong.Line(time: Double($0.offset) * 4, text: $0.element) }
        return LiveSong(title: "Velvet Rope", artist: "The Review Room House Band",
                        startedAt: ISO8601DateFormatter().string(from: started.addingTimeInterval(-3)), lines: lines)
    }
}
