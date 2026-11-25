import Foundation
import Testing
import AudienceKit
import StaffKitCore
import StaffKitServices

// The same digests the API's LyricTiming.line_hash gives (spec/models/lyric_timing_spec.rb).
@Test func lyricLineDigestsMatchTheAPIs() {
    #expect(LyricTimingDigest.normalized("Don\u{2019}t cry for me, Argentina!") == "dont cry for me argentina")
    #expect(LyricTimingDigest.digest("Don't cry for me, Argentina!") == "1383a8d85b36ff47")
    #expect(LyricTimingDigest.digest("  Something has changed within me ") == "e4616c2b6d42b29c")
    #expect(LyricTimingDigest.normalized("Café — ½ 12") == "cafe 1 2 12")
    #expect(LyricTimingDigest.digest("Café — ½ 12") == "ca454435266513e9")
    #expect(LyricTimingDigest.digest("") == "e3b0c44298fc1c14")
}

@Test func aSharedTimingJoinsTheWordsFromAnotherSource() throws {
    let timed = try #require(SyncedLyrics.lrc("[00:10.00]Something has changed within me\n[00:13.50]\n[00:14.00]Something is not the same\n[00:18.25]I'm through with playing by the rules"))
    let timing = SharedLyricTiming(spotifyTrackId: "4cOdK2wGLETKBW3PvgPWqT", title: "Defying Gravity", matchedLines: 3,
                                   lines: SharedLyricTiming.lines(of: timed))
    #expect(timing.lines.count == 3)
    #expect(timing.lines.allSatisfy { $0.digest.count == 16 })
    // The licensed source's text: different punctuation and an extra line still line up.
    let joined = try #require(timing.joined(with: "SOMETHING has changed within me...\n(Elphaba)\nSomething is not the same!\nIm through with playing by the rules\n"))
    #expect(joined.lines.map(\.time) == [10, 14, 18.25])
    #expect(joined.lines.first?.text == "SOMETHING has changed within me...")
    // A different song's words don't fit.
    #expect(timing.joined(with: "Popular\nYou're gonna be popular") == nil)
}

@Test func aDeviceSharesATimingWithoutTheWords() async throws {
    let stub = Stub { request in
        let body = String(data: request.body ?? Data(), encoding: .utf8) ?? ""
        if body.contains("reportLyricTiming") {
            return .json(status: 200, body: #"{"data":{"reportLyricTiming":{"lyricTiming":{"spotifyTrackId":"4cOdK2wGLETKBW3PvgPWqT","title":"Defying Gravity","matchedLines":1,"lines":[{"time":10.0,"digest":"e4616c2b6d42b29c"}]}}}}"#)
        }
        return .json(status: 200, body: #"{"data":{"venues":{"venue":{"music":{"lyricTimings":[{"spotifyTrackId":"4cOdK2wGLETKBW3PvgPWqT","title":"Defying Gravity","matchedLines":1,"lines":[{"time":10.0,"digest":"e4616c2b6d42b29c"}]}]}}}}}"#)
    }
    let client = VenueManagementClient(session: AudienceManagementSession(baseURL: stub.baseURL, credentialStore: InMemoryCredentialStore(credential: makeCredential(audienceID: "audience", on: stub.baseURL)), session: stub.session))
    let lyrics = try #require(SyncedLyrics.lrc("[00:10.00]Something has changed within me"))
    let kept = try await client.reportLyricTiming(spotifyTrackID: "spotify:track:4cOdK2wGLETKBW3PvgPWqT", title: "Defying Gravity",
                                                  artist: "Idina Menzel", duration: 353, lyrics: lyrics, matchedLines: 5,
                                                  source: "velvet-aligner")
    #expect(kept.matchedLines == 1)
    let sent = try #require(stub.requests.last)
    let body = String(data: sent.body ?? Data(), encoding: .utf8) ?? ""
    #expect(!body.contains("Something has changed"))
    let variables = try #require(sent.jsonBody()["variables"] as? [String: Any])
    #expect(variables["id"] as? String == "4cOdK2wGLETKBW3PvgPWqT")
    #expect(variables["matched"] as? Int == 1)
    #expect(variables["duration"] as? Int == 353_000)
    let fetched = try await client.lyricTiming(venueID: "venue", spotifyTrackID: "4cOdK2wGLETKBW3PvgPWqT")
    #expect(fetched?.lines.first?.digest == "e4616c2b6d42b29c")
}

@Test func aMacWithoutAKeyGetsTheWordsFromTheAPI() async throws {
    let stub = Stub { _ in
        .json(status: 200, body: #"{"data":{"venues":{"venue":{"music":{"lyricTimings":[{"spotifyTrackId":"4cOdK2wGLETKBW3PvgPWqT","title":"Defying Gravity","matchedLines":2,"lines":[{"time":10.0,"digest":"e4616c2b6d42b29c"},{"time":14.0,"digest":"0000000000000000"}],"syncedLines":[{"time":14.0,"text":"Something is not the same"},{"time":10.0,"text":"Something has changed within me"}]}]}}}}}"#)
    }
    let client = VenueManagementClient(session: AudienceManagementSession(baseURL: stub.baseURL, credentialStore: InMemoryCredentialStore(credential: makeCredential(audienceID: "audience", on: stub.baseURL)), session: stub.session))
    let fetched = try #require(try await client.lyricTiming(venueID: "venue", spotifyTrackID: "4cOdK2wGLETKBW3PvgPWqT", words: true))
    let body = String(data: stub.requests.last?.body ?? Data(), encoding: .utf8) ?? ""
    #expect(body.contains("syncedLines { time text }"))
    let lyrics = try #require(fetched.syncedLyrics)
    #expect(lyrics.lines.map(\.time) == [10, 14])
    #expect(lyrics.lines.first?.text == "Something has changed within me")
    // Without asking, the words aren't requested and there are none.
    _ = try await client.lyricTiming(venueID: "venue", spotifyTrackID: "4cOdK2wGLETKBW3PvgPWqT")
    let plain = String(data: stub.requests.last?.body ?? Data(), encoding: .utf8) ?? ""
    #expect(plain.contains("syncedLines") == false)
    #expect(SharedLyricTiming(spotifyTrackId: "x", title: "x", matchedLines: 0, lines: []).syncedLyrics == nil)
}

// Phase 2 of #294: a Mac's aligned syllables shared with every venue, by length and time, never the words.
@Test func syllableTimingIsSharedByLengthWithoutMismatchedLines() {
    let digest = LyricTimingDigest.digest("Defying gravity")
    let timing = SyllableTiming(
        recording: MediaRecording(title: "Defying Gravity", spotifyTrackIds: ["4cOdK2wGLETKBW3PvgPWqT"]),
        lyricVersion: "v", model: "m",
        lines: [
            SyllableTiming.Line(digest: digest, start: 10.004, end: 12, syllables: [
                SyllableTiming.Syllable(length: 2, start: 10.004, end: 10.3, confidence: 0.912),
                SyllableTiming.Syllable(length: 2, start: 10.3, end: 10.6),
                SyllableTiming.Syllable(length: 4, start: 10.6, end: 11),
                SyllableTiming.Syllable(length: 3, start: 11, end: 11.3),
                SyllableTiming.Syllable(length: 2, start: 11.3, end: 11.6),
                SyllableTiming.Syllable(length: 2, start: 11.6, end: 12),
            ]),
            SyllableTiming.Line(digest: "", start: 12, end: 14, syllables: []),
            SyllableTiming.Line(digest: LyricTimingDigest.digest("Not sung here"), start: 14, end: 15,
                                syllables: [SyllableTiming.Syllable(length: 13, start: 14, end: 15)], flag: "mismatch"),
        ])
    let lines = SharedLyricTiming.lines(of: timing)
    #expect(lines.count == 1)
    #expect(lines[0].time == 10)
    #expect(lines[0].syllables?.first == SyllableTiming.Syllable(length: 2, start: 10, end: 10.3, confidence: 0.91))
}

@Test func sharedSyllablesCutTheWordsFromAnotherSource() throws {
    let lyrics = try #require(SyncedLyrics.lrc("[00:10.25]DEFYING gravity!\n[00:14.00]Something else entirely"))
    let shared = SharedLyricTiming(spotifyTrackId: "4cOdK2wGLETKBW3PvgPWqT", title: "Defying Gravity", matchedLines: 1,
                                   lines: [.init(time: 10, digest: LyricTimingDigest.digest("Defying gravity"), syllables: [
                                       .init(length: 2, start: 10, end: 10.3), .init(length: 2, start: 10.3, end: 10.6),
                                       .init(length: 4, start: 10.6, end: 11), .init(length: 3, start: 11, end: 11.3),
                                       .init(length: 2, start: 11.3, end: 11.6), .init(length: 3, start: 11.6, end: 12),
                                   ])])
    #expect(shared.syllableLines == 1)
    let captions = try #require(shared.syllables(with: lyrics))
    // The first line takes the shared syllables, moved a quarter second to this venue's line time; the second, with
    // no shared syllables, is spread over its line timing.
    #expect(captions.lines.count == 2)
    #expect(captions.lines[0].syllables.map(\.text) == ["DE", "FY", "ING ", "gra", "vi", "ty!"])
    #expect(captions.lines[0].syllables.first?.start == 10.25)
    #expect(captions.lines[0].end == 12.25)
    #expect(captions.lines[1].start == 14)
    #expect(!captions.lines[1].syllables.isEmpty)
    // The same words sung twenty seconds later are another line: no syllables found is nil.
    let other = try #require(SyncedLyrics.lrc("[00:30.00]Defying gravity"))
    #expect(shared.syllables(with: other) == nil)
    #expect(SharedLyricTiming(spotifyTrackId: "x", title: "x", matchedLines: 0, lines: [.init(time: 1, digest: "a")])
        .syllables(with: lyrics) == nil)
}

@Test func aMacSharesSyllablesAndReadsThemBackFallingBackOnAnOlderAPI() async throws {
    let stub = Stub { request in
        let body = String(data: request.body ?? Data(), encoding: .utf8) ?? ""
        if body.contains("reportLyricTiming") {
            return .json(status: 200, body: #"{"data":{"reportLyricTiming":{"lyricTiming":{"spotifyTrackId":"4cOdK2wGLETKBW3PvgPWqT","title":"Defying Gravity","matchedLines":1,"lines":[{"time":10.0,"digest":"e4616c2b6d42b29c","syllables":[{"length":31,"start":10.0,"end":12.0,"confidence":null}]}]}}}}"#)
        }
        if body.contains("syllables") {
            return .json(status: 200, body: #"{"errors":[{"message":"Field 'syllables' doesn't exist on type 'LyricTimingLine'"}]}"#)
        }
        return .json(status: 200, body: #"{"data":{"venues":{"venue":{"music":{"lyricTimings":[{"spotifyTrackId":"4cOdK2wGLETKBW3PvgPWqT","title":"Defying Gravity","matchedLines":1,"lines":[{"time":10.0,"digest":"e4616c2b6d42b29c"}]}]}}}}}"#)
    }
    let client = VenueManagementClient(session: AudienceManagementSession(baseURL: stub.baseURL, credentialStore: InMemoryCredentialStore(credential: makeCredential(audienceID: "audience", on: stub.baseURL)), session: stub.session))
    let timing = SyllableTiming(
        recording: MediaRecording(title: "Defying Gravity", artist: "Idina Menzel", duration: 353),
        lyricVersion: "v", model: "m",
        lines: [SyllableTiming.Line(digest: "e4616c2b6d42b29c", start: 10, end: 12,
                                    syllables: [SyllableTiming.Syllable(length: 31, start: 10, end: 12)])])
    let kept = try #require(try await client.reportSyllableTiming(timing, spotifyTrackID: "4cOdK2wGLETKBW3PvgPWqT"))
    #expect(kept.syllableLines == 1)
    let sent = try #require(stub.requests.last)
    let variables = try #require(sent.jsonBody()["variables"] as? [String: Any])
    let line = try #require((variables["lines"] as? [[String: Any]])?.first)
    let syllable = try #require((line["syllables"] as? [[String: Any]])?.first)
    #expect(syllable["length"] as? Int == 31)
    #expect(syllable["confidence"] == nil)
    #expect(variables["matched"] as? Int == 1)
    #expect(variables["source"] as? String == "velvet-aligner")
    // Production before shared syllables: the line timing still comes through.
    let fetched = try await client.lyricTiming(venueID: "venue", spotifyTrackID: "4cOdK2wGLETKBW3PvgPWqT")
    #expect(fetched?.lines.first?.digest == "e4616c2b6d42b29c")
    #expect(fetched?.syllableLines == 0)
}
