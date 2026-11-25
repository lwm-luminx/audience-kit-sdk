import Foundation
import Testing
@testable import StaffKitServices

// Syllable captions for the sing-along screen: the syllabifier, the Velvet JSON timing file joined back to the words,
// TTML both ways, and the media identity model (cache keys, medleys and mashups, film fingerprint anchors).

@Test func syllablesJoinBackIntoTheLine() {
    for line in ["Defying gravity!", "(Oh) I dreamed a dream in time gone by", "Don't stop me now", "♪", "",
                 "  Little table, rhythm and blues  ", "Supercalifragilisticexpialidocious"] {
        #expect(Syllabifier.syllables(line).joined() == line, "\(line)")
    }
    #expect(Syllabifier.syllables("Defying gravity") == ["De", "fy", "ing ", "gra", "vi", "ty"])
    #expect(Syllabifier.syllables("little table") == ["lit", "tle ", "ta", "ble"])
    #expect(Syllabifier.syllables("I loved the time") == ["I ", "loved ", "the ", "time"])
    #expect(Syllabifier.syllables("(Oh") == ["(Oh"])
}

@Test func estimatedSyllablesShareTheirLinesTime() throws {
    let lyrics = try #require(SyncedLyrics.lrc("[00:10.00]Defying gravity\n[00:14.00]\n[00:40.00]Down"))
    let estimated = SyllableLyrics.estimated(from: lyrics, duration: 45)
    #expect(estimated.estimated)
    #expect(estimated.lines.count == 3)
    let first = estimated.lines[0]
    #expect(first.text == "Defying gravity")
    #expect(first.syllables.first?.start == 10)
    // Six syllables at most 0.55 s each plus 0.4: done well before the next line.
    #expect(first.end <= 10 + 6 * 0.55 + 0.4 + 0.0001)
    #expect(zip(first.syllables, first.syllables.dropFirst()).allSatisfy { abs($0.end - $1.start) < 0.0001 })
    // The instrumental break has no syllables.
    #expect(estimated.lines[1].syllables.isEmpty)
    #expect(estimated.index(at: 12) == 0)
    #expect(estimated.index(at: 41) == 2)
    let syllable = first.syllables[0]
    #expect(SyllableLyrics.fill(syllable, at: syllable.start - 1) == 0)
    #expect(abs(SyllableLyrics.fill(syllable, at: (syllable.start + syllable.end) / 2) - 0.5) < 1e-9)
    #expect(SyllableLyrics.fill(syllable, at: syllable.end + 1) == 1)
}

@Test func timingFilesHoldNoWordsAndJoinBackToThem() throws {
    let lyrics = SyllableLyrics(lines: [
        .init(start: 1, end: 2.5, syllables: [.init(text: "Hel", start: 1, end: 1.4, confidence: 0.9),
                                              .init(text: "lo ", start: 1.4, end: 2, confidence: 0.8),
                                              .init(text: "world", start: 2, end: 2.5, confidence: 0.3)],
              mismatch: true),
        .init(start: 3, end: 6, syllables: []),
        .init(start: 6, end: 7, syllables: [.init(text: "Café", start: 6, end: 7)]),
    ])
    let recording = MediaRecording(title: "Greeting", artist: "Someone", isrc: "us-abc-26-00001")
    let timing = SyllableTiming(lyrics: lyrics, recording: recording, model: "test/1")
    let json = String(decoding: try JSONEncoder().encode(timing), as: UTF8.self)
    #expect(!json.contains("Hel") && !json.contains("world") && !json.contains("Caf"))
    let decoded = try JSONDecoder().decode(SyllableTiming.self, from: Data(json.utf8))
    #expect(decoded.format == SyllableTiming.currentFormat)
    #expect(decoded.lines[0].syllables.map(\.length) == [3, 3, 5])
    #expect(decoded.lines[0].flag == "mismatch")

    // Joined to the words from elsewhere, punctuation and case aside, with an extra line of text in between.
    let joined = try #require(decoded.joined(with: ["Intro talk", "Hello world", "Café"]))
    #expect(joined.lines.map(\.text) == ["Hello world", "", "Café"])
    #expect(joined.lines[0].mismatch)
    #expect(joined.lines[0].syllables[2].confidence == 0.3)
    #expect(!joined.estimated)
    // Words for another song: nothing.
    #expect(decoded.joined(with: ["Something else entirely"]) == nil)
    // Same digest, different spelling length: that line can't be cut, so it's left out.
    #expect(decoded.joined(with: ["Hello, world!", "Cafe"])?.lines.map(\.text) == ["", "Cafe"])

    #expect(timing.cacheKey.hasPrefix("isrc:USABC2600001|"))
    #expect(timing.fileName.count == 29)
    #expect(timing.lyricVersion == SyllableTiming.lyricVersion(of: ["Hello world", "", "Café"]))
}

@Test func ttmlRoundTripsSyllableLyrics() throws {
    let lyrics = SyllableLyrics(lines: [
        .init(start: 1, end: 2.5, syllables: [.init(text: "Hel", start: 1, end: 1.4), .init(text: "lo ", start: 1.4, end: 2),
                                              .init(text: "you & me", start: 2, end: 2.5)]),
        .init(start: 3, end: 4, syllables: [.init(text: "Bye", start: 3, end: 4)]),
    ])
    let ttml = SyllableTTML.document(lyrics, title: "Hello", artist: "Someone")
    #expect(ttml.contains(#"<span begin="00:00:01.000" end="00:00:01.400">Hel</span>"#))
    #expect(ttml.contains("you &amp; me"))
    let read = try #require(SyllableTTML.lyrics(ttml))
    #expect(read.lines.map(\.text) == ["Hello you & me", "Bye"])
    #expect(read.lines[0].syllables.map(\.start) == [1, 1.4, 2])
    #expect(!read.estimated)
}

@Test func lineTimedTTMLIsSpreadOverItsLines() throws {
    let ttml = """
        <tt xmlns="http://www.w3.org/ns/ttml"><body><div>
          <p begin="12.5s" end="15s">Defying gravity</p>
          <p begin="00:20.000" dur="2s">
            <span begin="00:20.000" end="00:20.500">Kiss</span> <span begin="00:20.500" end="00:21.000">me</span>
          </p>
        </div></body></tt>
        """
    let read = try #require(SyllableTTML.lyrics(ttml))
    #expect(read.estimated)
    #expect(read.lines.count == 2)
    #expect(read.lines[0].text == "Defying gravity")
    #expect(read.lines[0].start == 12.5 && read.lines[0].end == 15)
    #expect(read.lines[1].text == "Kiss me")
    #expect(read.lines[1].end == 22)
    #expect(SyllableTTML.seconds("1:02:03.5") == 3723.5)
    #expect(SyllableTTML.seconds("1500ms") == 1.5)
    #expect(SyllableTTML.seconds("soon") == nil)
}

@Test func recordingKeysPreferStableIdentifiers() {
    var recording = MediaRecording(title: "Song", artist: "Artist", album: "Album")
    #expect(recording.key.hasPrefix("meta:"))
    #expect(recording.key == MediaRecording(title: "song!", artist: "ARTIST", album: "album").key)
    recording.fingerprint = "AQAAz0mUaEkSRYmS"
    #expect(recording.key.hasPrefix("fp:"))
    recording.isrc = "GB-AYE-05-00001"
    #expect(recording.key == "isrc:GBAYE0500001")
    recording.musicbrainzRecordingId = "B1A9C0E9-D987-4042-AE91-78D6A3267D69"
    #expect(recording.key == "mbid:b1a9c0e9-d987-4042-ae91-78d6a3267d69")
}

@Test func medleysSwitchWorksAndMashupsOnlyAttribute() {
    let a = MediaWork(title: "A"), b = MediaWork(title: "B")
    #expect(RecordingWorkLink.plan(for: [], at: 10) == .captions(nil))
    #expect(RecordingWorkLink.plan(for: [.init(work: a, kind: .cover)], at: 10) == .captions(a))
    let medley = [RecordingWorkLink(work: a, kind: .medley, start: 0, end: 105),
                  RecordingWorkLink(work: b, kind: .medley, start: 110)]
    #expect(RecordingWorkLink.plan(for: medley, at: 30) == .captions(a))
    #expect(RecordingWorkLink.plan(for: medley, at: 107) == CaptionPlan.none)
    #expect(RecordingWorkLink.plan(for: medley, at: 200) == .captions(b))
    let overlapping = [RecordingWorkLink(work: a, kind: .medley, start: 0, end: 120),
                       RecordingWorkLink(work: b, kind: .medley, start: 60)]
    #expect(RecordingWorkLink.plan(for: overlapping, at: 10) == .attribution([a, b]))
    #expect(RecordingWorkLink.plan(for: [.init(work: a, kind: .mashup)], at: 10) == .attribution([a]))
}

@Test func fingerprintAnchorsAreFoundBySoundNotOffset() throws {
    var values: [UInt32] = (0..<400).map { UInt32(truncatingIfNeeded: $0 &* 2_654_435_761) }
    let anchor = Array(values[200..<240])
    // Another edition: 37 sub-fingerprints cut ahead of the song, a couple of bits off in the anchor.
    values.removeFirst(37)
    values[170] ^= 0b101
    let film = MediaVideoWork(imdbId: "tt1707386", title: "Les Misérables", timeline: FingerprintTimeline(values: values))
    let found = try #require(film.timeline?.find(anchor))
    #expect(abs(found.time - 163 / FingerprintTimeline.chromaprintRate) < 0.001)
    #expect(found.similarity > 0.99)
    #expect(film.timeline?.find((0..<40).map { _ in UInt32(0x5555_5555) }, threshold: 0.9) == nil)
}

// Line-only captions until the aligner has run, and a musical note through instrumental stretches.
@Test func onlyMeasuredSyllablesSweep() throws {
    let lyrics = try #require(SyncedLyrics.lrc("[00:10.00]Defying gravity\n[00:40.00]Down"))
    let estimated = SyllableLyrics.estimated(from: lyrics, duration: 45)
    #expect(estimated.lines.allSatisfy { !$0.sweeps })
    let aligned = SyllableLyrics.Line(start: 1, end: 2, syllables: [.init(text: "Hi", start: 1, end: 2, confidence: 0.9)])
    #expect(aligned.sweeps)
    var flagged = aligned
    flagged.mismatch = true
    #expect(!flagged.sweeps)
    // A TTML file timed line by line is spread, so it's lit by line too; one timed word by word sweeps.
    let lineTimed = try #require(SyllableTTML.lyrics(
        "<tt xmlns=\"http://www.w3.org/ns/ttml\"><body><div><p begin=\"00:01.000\" end=\"00:03.000\">Hello world</p></div></body></tt>"))
    #expect(lineTimed.lines.allSatisfy { !$0.sweeps })
    let wordTimed = try #require(SyllableTTML.lyrics(
        "<tt xmlns=\"http://www.w3.org/ns/ttml\"><body><div><p begin=\"00:01.000\" end=\"00:03.000\"><span begin=\"00:01.000\" end=\"00:02.000\">Hello</span> <span begin=\"00:02.000\" end=\"00:03.000\">world</span></p></div></body></tt>"))
    #expect(wordTimed.lines.allSatisfy { $0.sweeps })
}

@Test func longStretchesWithNothingSungBecomeInstrumentalBreaks() throws {
    // A 10 s intro, a long gap between the lines, and a long outro.
    let lyrics = try #require(SyncedLyrics.lrc("[00:10.00]Defying gravity\n[00:40.00]Down"))
    let captions = SyllableLyrics.estimated(from: lyrics).withBreaks(duration: 60)
    #expect(captions.lines.map(\.syllables.isEmpty) == [true, false, true, false, true])
    #expect(captions.lines[0].start == 0)
    // The break waits a second after the line's last syllable.
    let sungUntil = try #require(captions.lines[1].syllables.last?.end)
    #expect(abs(captions.lines[2].start - (sungUntil + 1)) < 1e-9)
    #expect(captions.index(at: 5) == 0)
    #expect(captions.index(at: 30) == 2)
    // Short gaps get no break, and a song's own instrumental line isn't doubled.
    let tight = try #require(SyncedLyrics.lrc("[00:02.00]One\n[00:05.00]Two\n[00:07.00]\n[00:30.00]Three"))
    #expect(SyllableLyrics.estimated(from: tight).withBreaks().lines.map(\.syllables.isEmpty) == [false, false, true, false])
}
