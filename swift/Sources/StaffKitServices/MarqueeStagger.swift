import Foundation

/// A screen's place among the venue's screens showing the board, so they take their breaks in turn, not all at once
/// (Rick, 2026-11-23: "if we have many screens ... they can show the 'all' differently - e.g. lineup / posters").
///
/// Every board looks at the lineup for `MarqueeSlide.boardSeconds` and then shows a slide for
/// `MarqueeSlide.slideSeconds`. Alone, a screen keeps its own time. With others, the cycle is laid on the clock and
/// each screen starts its break `index / count` of a cycle after the first, so while one shows a poster the rest
/// still show the lineup, and each starts a different kind of slide (poster, photo, slogan, safety). Screens need no
/// word from each other: each reads the venue's displays, finds its place by ID, and reads the clock. A screen
/// showing a live activity (a game, a sing-along) takes no breaks at all, so it stays on it.
///
/// The Google TV board keeps the same rule (`VelvetTvLogic`), so Apple and Google screens at one venue take turns too.
public struct MarqueeStagger: Sendable, Hashable {
    /// This screen's place, from 0, among the venue's board screens in ID order.
    public let index: Int
    /// How many of the venue's screens show the board now.
    public let count: Int

    public static let alone = MarqueeStagger(index: 0, count: 1)

    public init(index: Int, count: Int) {
        self.count = max(count, 1)
        self.index = min(max(index, 0), self.count - 1)
    }

    /// The place of the display `id` among `displays`: those not off that rank the board or the lineup, and are
    /// connected now (this one always counts), in ID order. Alone when it isn't one of them.
    public static func of(_ id: String, among displays: [StaffVenueDisplay], now: Date = Date()) -> MarqueeStagger {
        let boards = displays.filter { display in
            !display.off && display.ranking.contains { $0.type == .board || $0.type == .lineup }
                && (display.id == id || display.connection(now: now) == .connected)
        }.map(\.id).sorted()
        guard let index = boards.firstIndex(of: id) else { return .alone }
        return MarqueeStagger(index: index, count: boards.count)
    }

    /// How long this screen looks at the lineup from `now` before its next break. Alone, the usual `board` seconds.
    /// With others, until its next turn on the clock; a turn under half a look away is left for the one after, so
    /// a screen that just came back from a slide (or just started) never flashes straight to another.
    public func wait(from now: Date = Date(), board: Double = MarqueeSlide.boardSeconds,
                     slide: Double = MarqueeSlide.slideSeconds) -> Double {
        guard count > 1 else { return board }
        let cycle = board + slide
        let since = Self.positive(now.timeIntervalSince1970 - offset(cycle: cycle), modulo: cycle)
        let wait = cycle - since
        return wait < board / 2 ? wait + cycle : wait
    }

    /// Which break of the venue's this is for this screen at `date`: one more each cycle, and one apart from the
    /// screen before, so neighbours start on different kinds of slide. Alone, nil: the screen counts its own.
    public func turn(at date: Date = Date(), board: Double = MarqueeSlide.boardSeconds,
                     slide: Double = MarqueeSlide.slideSeconds) -> Int? {
        guard count > 1 else { return nil }
        let cycle = board + slide
        // The break that starts nearest `date`: a screen woken a moment early or late still counts the same one.
        let slot = ((date.timeIntervalSince1970 - offset(cycle: cycle)) / cycle).rounded()
        return Int(Self.positive(slot + Double(index), modulo: 1_000_000))
    }

    private func offset(cycle: Double) -> Double { Double(index) * cycle / Double(count) }

    private static func positive(_ value: Double, modulo: Double) -> Double {
        let rest = value.truncatingRemainder(dividingBy: modulo)
        return rest < 0 ? rest + modulo : rest
    }
}
