import Foundation
import Testing
@testable import StaffKitServices

// The sing-along screen's lyrics in time (LRC) and the song clock it runs on.

@Test func lrcReadsStampsRepeatsAndOffset() throws {
    let lyrics = try #require(SyncedLyrics.lrc("""
        [ar:Someone]
        [ti:A Song]
        [offset:+500]
        [00:12.50]First line
        [00:20.00][01:05.25]Chorus line
        [00:30:10]
        [00:40]Last line
        not timed at all
        """))
    #expect(lyrics.lines.map(\.text) == ["First line", "Chorus line", "", "Last line", "Chorus line"])
    #expect(lyrics.lines.map(\.time) == [12, 19.5, 29.6, 39.5, 64.75])
    #expect(SyncedLyrics.lrc("[ar:Nobody]\nno times here") == nil)
}

@Test func theLineBeingSungIsTheLastStarted() throws {
    let lyrics = try #require(SyncedLyrics.lrc("[00:10.00]One\n[00:20.00]Two\n[00:30.00]Three"))
    #expect(lyrics.index(at: 5) == nil)
    #expect(lyrics.index(at: 10) == 0)
    #expect(lyrics.index(at: 25) == 1)
    #expect(lyrics.index(at: 300) == 2)
}

@Test func theSongClockRunsOnlyWhilePlaying() {
    let read = Date(timeIntervalSince1970: 1000)
    let playing = PlaybackClock(trackID: "t", position: 30, readAt: read, playing: true, duration: 40)
    #expect(playing.position(at: read.addingTimeInterval(5)) == 35)
    #expect(playing.position(at: read.addingTimeInterval(60)) == 40)
    #expect(playing.position(at: read.addingTimeInterval(-3)) == 30)
    let paused = PlaybackClock(trackID: "t", position: 30, readAt: read, playing: false)
    #expect(paused.position(at: read.addingTimeInterval(5)) == 30)
}
