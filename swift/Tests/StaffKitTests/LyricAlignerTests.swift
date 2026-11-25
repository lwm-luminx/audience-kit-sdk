import Foundation
import Testing
@testable import StaffKitServices

// Timing lyric lines from a transcript of the song, for an LRC file in Velvet Display's lyrics folder.

private func heard(_ text: String, from start: TimeInterval, every step: TimeInterval = 0.5) -> [LyricAligner.Word] {
    text.split(separator: " ").enumerated().map { LyricAligner.Word(text: String($0.element), time: start + Double($0.offset) * step) }
}

@Test func linesTakeTheTimeTheirOpeningWordsWereHeard() {
    let lyrics = """
        [Verse 1]
        Twinkle twinkle little star
        How I wonder what you are

        Up above the world so high
        Like a diamond in the sky
        """
    // The recognizer mishears "wonder" and "diamond", misses a whole line and adds a stray word.
    let words = heard("oh", from: 1) + heard("Twinkle twinkle little star", from: 10)
        + heard("how I wander what you are", from: 14) + heard("like a dimond in the sky", from: 22)
    let synced = LyricAligner.align(lyrics: lyrics, words: words, duration: 30)
    #expect(synced.lines.map(\.text) == ["Twinkle twinkle little star", "How I wonder what you are",
                                         "Up above the world so high", "Like a diamond in the sky"])
    #expect(synced.lines[0].time == 10)
    #expect(synced.lines[1].time == 14)
    #expect(synced.lines[3].time == 22)
    // The missed line falls between its neighbours.
    #expect(synced.lines[2].time > 14 && synced.lines[2].time < 22)
}

@Test func unmatchedLinesNeverGoBackwards() {
    let synced = LyricAligner.align(lyrics: "one two three\nfour five six\nseven eight nine",
                                    words: heard("seven eight nine", from: 5), duration: 12)
    let times = synced.lines.map(\.time)
    #expect(times == times.sorted())
    #expect(times.last == 5)
}

@Test func lrcTextReadsBackTheSame() {
    let synced = SyncedLyrics(lines: [.init(time: 10, text: "Twinkle twinkle little star"), .init(time: 74.5, text: "How I wonder")])
    let text = synced.lrcText(title: "Twinkle", artist: "Traditional")
    #expect(text.hasPrefix("[ar:Traditional]\n[ti:Twinkle]\n[00:10.00]Twinkle twinkle little star\n[01:14.50]How I wonder"))
    #expect(SyncedLyrics.lrc(text)?.lines == synced.lines)
}

@Test func similarWordsForgiveOneSlip() {
    #expect(LyricAligner.similar("wonder", "wander"))
    #expect(LyricAligner.similar("diamond", "dimond"))
    #expect(LyricAligner.similar("star", "stay"))
    #expect(!LyricAligner.similar("a", "i"))
    #expect(LyricAligner.distance("kitten", "sitting") == 3)
}
