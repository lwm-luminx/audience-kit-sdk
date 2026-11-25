import Foundation
import Testing
import StaffKitServices
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// A test signal: half-second chords stepped by a linear congruential generator, at 11025 Hz. The expected values are
// what `fpcalc -raw` (Chromaprint 1.5.1) printed for the same samples written to a WAV file.
private func chords(seconds: Int = 12, rate: Int = 11025) -> [Int16] {
    var state: UInt64 = 12345, base = 0.0, out: [Int16] = []
    for n in 0..<(seconds * rate) {
        if n % (rate / 2) == 0 {
            state = (state &* 1103515245 &+ 12345) % 2147483648
            base = 220 * pow(2, Double(state % 24) / 12)
        }
        let t = Double(n) / Double(rate)
        let v = 6000 * (sin(2 * .pi * base * t) + 0.5 * sin(2 * .pi * base * 1.5 * t) + 0.3 * sin(2 * .pi * base * 2 * t))
        out.append(Int16(v.rounded()))
    }
    return out
}

private let fpcalcRaw: [UInt32] = [
    3467129002, 3467129002, 3450347689, 3433652392, 3433685160, 3438129580,
    3429208488, 3425801128, 3442705128, 3442641464, 3476220427, 1328736778,
    1244817930, 1261644298, 1269840138, 1336939530, 1336672346, 1302855870,
    1302937764, 1302978720, 1282056352, 1277866384, 69636480, 69374848,
    69370560, 19040768, 320907812, 304130596, 841001516, 572566313,
    572586042, 572543002, 572522730, 841220266, 845037738, 542032042,
    550416810, 546223722, 546290191, 546286095, 546154767, 546744333,
    559331341, 573750287, 573751310, 1647444030, 1647444014, 1647453166,
    1649615534, 1652564654, 1635794614, 1887442562, 1887699586, 1350566529,
    1350582912, 1082167988, 1077981852, 1343274504, 1395829256, 1378003464,
    1378003464, 1378069002, 1377957898, 1377833994, 1377828922, 1130364970,
    1084162090, 1083048042, 1083061098, 1083060841, 1082995304, 1082981992,
    1087158856, 1075624520, 1128184520,
]

private let fpcalcCompressed = "AQAAS5LUWFKyAMkf5DqOmSKxm_glXOxRhUWyPEeOX7iOZ4xxRUdFOcGW_JByYReuNEEzHn3z4cdFPLywnR8OHpGPZMwEW0KTVPiPT0nwdjiT40lyRAtTHM-hPwr-BPoXBXmSoHmO4kmI6w2eKWCcPJhinbiM5EeOKVcO6g-mLZdxlQtOQMen4VESNBV6EU-SJAl-4lmQHHnwLIHL4wp-LgCknJDIEAAEgpNAQQhDwCBoiDAEACYEORsoAyUhQDEigGCGCEMgAIIqhChygAlCEIcGWQoMARIJLgw"

@Test func chromaprintMatchesFpcalc() {
    let fingerprint = Chromaprint.fingerprint(chords())
    #expect(fingerprint.count == fpcalcRaw.count)
    let differing = zip(fingerprint, fpcalcRaw).reduce(0) { $0 + ($1.0 ^ $1.1).nonzeroBitCount }
    #expect(differing == 0)
    #expect(Chromaprint.compress(fpcalcRaw) == fpcalcCompressed)
}

@Test func chromaprintStreamsInAnyChunks() {
    let samples = chords(seconds: 6)
    var printer = Chromaprint()
    var index = 0
    for size in [1, 500, 4095, 4097, 1365, 10000] where index < samples.count {
        printer.consume(samples[index..<min(samples.count, index + size)])
        index += size
    }
    printer.consume(samples[min(index, samples.count)...])
    #expect(printer.fingerprint == Chromaprint.fingerprint(samples))
    #expect(!printer.fingerprint.isEmpty)
    #expect(printer.compressed.hasPrefix("AQAA"))
}

@Test func chromaprintOfSilenceIsSteady() {
    let fingerprint = Chromaprint.fingerprint([Int16](repeating: 0, count: 11025 * 4))
    #expect(Set(fingerprint).count == 1)
}

@Test func aFingerprintFindsItselfInATimeline() throws {
    let timeline = FingerprintTimeline(values: Chromaprint.fingerprint(chords()))
    let slice = Array(timeline.values[30..<50])
    let found = try #require(timeline.find(slice))
    #expect(abs(found.time - 30 / FingerprintTimeline.chromaprintRate) < 0.001)
    #expect(found.similarity == 1)
}

// MARK: FLAC tags

private func le32(_ value: Int) -> [UInt8] { (0..<4).map { UInt8((value >> ($0 * 8)) & 255) } }

private func flac(comments: [String], seconds: Int = 200, rate: Int = 44100, picture: Int = 0) -> Data {
    var streamInfo = [UInt8](repeating: 0, count: 34)
    let samples = UInt64(seconds * rate)
    streamInfo[10] = UInt8((rate >> 12) & 255); streamInfo[11] = UInt8((rate >> 4) & 255)
    streamInfo[12] = UInt8((rate & 15) << 4) | 0x02 // two channels, rest of bits per sample left zero
    streamInfo[13] = UInt8((samples >> 32) & 0x0f)
    for index in 0..<4 { streamInfo[14 + index] = UInt8((samples >> UInt64(8 * (3 - index))) & 255) }
    var vorbis = le32(9) + Array("reference".utf8) + le32(comments.count)
    for comment in comments { vorbis += le32(comment.utf8.count) + Array(comment.utf8) }
    func block(_ type: UInt8, _ body: [UInt8], last: Bool = false) -> [UInt8] {
        [type | (last ? 0x80 : 0), UInt8((body.count >> 16) & 255), UInt8((body.count >> 8) & 255), UInt8(body.count & 255)] + body
    }
    var bytes = Array("fLaC".utf8) + block(0, streamInfo)
    if picture > 0 { bytes += block(6, [UInt8](repeating: 7, count: picture)) }
    bytes += block(4, vorbis, last: true)
    return Data(bytes)
}

@Test func flacTagsGiveTheRecordingsIdentifiers() async throws {
    let data = flac(comments: ["TITLE=Defying Gravity", "ARTIST=Idina Menzel", "ALBUM=Wicked (Original Broadway Cast)",
                               "isrc=USDW10310279", "MUSICBRAINZ_TRACKID=0b7f5c8f-1d55-4b8a-9b0e-6f0e7a3d4c21",
                               "BARCODE=602498617496", "TITLE=Second title"])
    let parsed = try #require(AudioFileTags.flac(data))
    #expect(parsed.duration == 200)
    #expect(parsed.comments["TITLE"] == "Defying Gravity")
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("velvet-test-\(UUID().uuidString).flac")
    try data.write(to: url)
    defer { try? FileManager.default.removeItem(at: url) }
    let recording = await AudioFileTags.recording(at: url)
    #expect(recording.title == "Defying Gravity")
    #expect(recording.artist == "Idina Menzel")
    #expect(recording.isrc == "USDW10310279")
    #expect(recording.musicbrainzRecordingId == "0b7f5c8f-1d55-4b8a-9b0e-6f0e7a3d4c21")
    #expect(recording.release?.barcode == "602498617496")
    #expect(recording.duration == 200)
    #expect(recording.key == "mbid:0b7f5c8f-1d55-4b8a-9b0e-6f0e7a3d4c21")
}

@Test func flacTagsAfterBigCoverArtAndNotFlac() throws {
    let data = flac(comments: ["TITLE=Popular"], picture: 300_000)
    #expect(AudioFileTags.flac(data)?.comments["TITLE"] == "Popular")
    #expect(AudioFileTags.flac(Data("ID3 not flac at all".utf8)) == nil)
}

// MARK: MusicBrainz and AcoustID

/// Answers each request from canned bodies by path, and keeps the requests.
private final class Canned: @unchecked Sendable {
    var bodies: [String: (Int, String)]
    var requests: [URLRequest] = []
    let lock = NSLock()
    init(_ bodies: [String: (Int, String)]) { self.bodies = bodies }

    func record(_ request: URLRequest) { lock.withLock { requests.append(request) } }

    var transport: HTTPTransport {
        { [self] request in
            record(request)
            let path = request.url!.path
            let (status, body) = bodies.first { path.hasSuffix($0.key) }?.value ?? (404, "{}")
            return (Data(body.utf8), HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
        }
    }
}

private let recordingJSON = """
{"id":"0b7f5c8f-1d55-4b8a-9b0e-6f0e7a3d4c21","title":"Defying Gravity","length":353000,"isrcs":["USDW10310279"],
 "artist-credit":[{"name":"Idina Menzel","joinphrase":" & ","artist":{"id":"a1","name":"Idina Menzel"}},
                  {"name":"Kristin Chenoweth","joinphrase":"","artist":{"id":"a2","name":"Kristin Chenoweth"}}],
 "releases":[{"id":"r2","title":"Wicked: 5th Anniversary","date":"2008","status":"Official"},
             {"id":"r1","title":"Wicked (Original Broadway Cast Recording)","date":"2003-12-16","status":"Official","barcode":"602498617496"}],
 "relations":[{"type":"performance","attributes":[],"work":{"id":"w1","title":"Defying Gravity","iswcs":["T-070.123.456-7"]}},
              {"type":"performance","attributes":["medley"],"work":{"id":"w2","title":"No Good Deed","iswcs":[]}}]}
"""

@Test func musicBrainzRecordingBecomesTheMediaIdentity() throws {
    let recording = try JSONDecoder().decode(MusicBrainzRecording.self, from: Data(recordingJSON.utf8))
    #expect(recording.artist == "Idina Menzel & Kristin Chenoweth")
    #expect(recording.duration == 353)
    #expect(recording.release?.id == "r1")
    #expect(recording.works.map(\.kind) == [.original, .medley])
    #expect(recording.works.first?.work.iswc == "T-070.123.456-7")
    let merged = recording.merged(into: MediaRecording(title: "Defying Gravity (from Wicked)", artist: "Idina Menzel"))
    #expect(merged.title == "Defying Gravity (from Wicked)")
    #expect(merged.artist == "Idina Menzel")
    #expect(merged.isrc == "USDW10310279")
    #expect(merged.musicbrainzRecordingId == "0b7f5c8f-1d55-4b8a-9b0e-6f0e7a3d4c21")
    #expect(merged.release?.barcode == "602498617496")
    #expect(merged.release?.artworkUrl == "https://coverartarchive.org/release/r1/front-500")
}

@Test func musicBrainzRequestsNameTheAppAndAskForJSON() async throws {
    let canned = Canned(["recording/0b7f5c8f-1d55-4b8a-9b0e-6f0e7a3d4c21": (200, recordingJSON)])
    let client = MusicBrainzClient(userAgent: MusicBrainzClient.userAgent(app: "VelvetDisplay", version: "1.0"),
                                   throttle: RequestThrottle(interval: .milliseconds(1)), transport: canned.transport)
    let found = try await client.recording(id: "0B7F5C8F-1D55-4B8A-9B0E-6F0E7A3D4C21")
    #expect(found?.title == "Defying Gravity")
    let request = try #require(canned.requests.first)
    #expect(request.value(forHTTPHeaderField: "User-Agent") == "VelvetDisplay/1.0 ( https://audiencekit.com )")
    let query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems ?? []
    #expect(query.contains(URLQueryItem(name: "fmt", value: "json")))
    #expect(query.contains(URLQueryItem(name: "inc", value: "artist-credits+isrcs+releases+work-rels")))
    #expect(try await client.recording(id: "00000000-0000-0000-0000-000000000000") == nil)
}

@Test func theThrottleSpacesRequests() async {
    let throttle = RequestThrottle(interval: .milliseconds(120))
    let clock = ContinuousClock()
    let start = clock.now
    for _ in 0..<3 { await throttle.turn() }
    #expect(clock.now - start >= .milliseconds(230))
}

@Test func identifyingPrefersTheISRCThenSearches() async throws {
    let isrcJSON = """
    {"isrc":"USDW10310279","recordings":[{"id":"other","title":"Defying Gravity","length":200000},
     {"id":"0b7f5c8f-1d55-4b8a-9b0e-6f0e7a3d4c21","title":"Defying Gravity","length":353500}]}
    """
    let canned = Canned(["isrc/USDW10310279": (200, isrcJSON),
                         "recording/0b7f5c8f-1d55-4b8a-9b0e-6f0e7a3d4c21": (200, recordingJSON),
                         "/ws/2/recording": (200, #"{"recordings":[{"id":"0b7f5c8f-1d55-4b8a-9b0e-6f0e7a3d4c21","score":97,"title":"Defying Gravity","length":352000}]}"#)])
    let client = MusicBrainzClient(userAgent: "Test/1", throttle: nil, transport: canned.transport)
    let identifier = SongIdentifier(musicBrainz: client)

    let byISRC = try await identifier.identify(MediaRecording(title: "Defying Gravity", isrc: "US-DW1-03-10279", duration: 353))
    #expect(byISRC.method == .isrc)
    #expect(byISRC.recording.musicbrainzRecordingId == "0b7f5c8f-1d55-4b8a-9b0e-6f0e7a3d4c21")
    #expect(byISRC.works.count == 2)

    let bySearch = try await identifier.identify(MediaRecording(title: "Defying Gravity", artist: "Idina Menzel", duration: 355))
    #expect(bySearch.method == .search)
    #expect(bySearch.confidence == 0.97)
    let search = try #require(canned.requests.last { $0.url!.path.hasSuffix("/ws/2/recording") })
    #expect(search.url!.absoluteString.contains("Idina"))

    // Too far off in length: not taken.
    let missed = try await identifier.identify(MediaRecording(title: "Defying Gravity", artist: "Idina Menzel", duration: 200))
    #expect(missed.method == .none)
}

@Test func identifyingByFingerprintGoesThroughAcoustID() async throws {
    let acoustJSON = """
    {"status":"ok","results":[{"id":"9ff43b6a-4f16-427c-93c2-92307ca505e0","score":0.93,"recordings":[
      {"id":"karaoke","title":"Defying Gravity (Karaoke)"},{"id":"0b7f5c8f-1d55-4b8a-9b0e-6f0e7a3d4c21","title":"Defying Gravity"}]},
      {"id":"low","score":0.2,"recordings":[{"id":"x"}]}]}
    """
    let canned = Canned(["/v2/lookup": (200, acoustJSON),
                         "recording/0b7f5c8f-1d55-4b8a-9b0e-6f0e7a3d4c21": (200, recordingJSON)])
    let identifier = SongIdentifier(
        musicBrainz: MusicBrainzClient(userAgent: "Test/1", throttle: nil, transport: canned.transport),
        acoustID: AcoustIDClient(key: "venue-key", throttle: RequestThrottle(interval: .milliseconds(1)), transport: canned.transport))
    let found = try await identifier.identify(MediaRecording(title: "Defying Gravity", fingerprint: "AQAAS5LU+/x", duration: 353.4))
    #expect(found.method == .fingerprint)
    #expect(found.acoustidId == "9ff43b6a-4f16-427c-93c2-92307ca505e0")
    #expect(found.recording.musicbrainzRecordingId == "0b7f5c8f-1d55-4b8a-9b0e-6f0e7a3d4c21")
    let lookup = try #require(canned.requests.first { $0.url!.path.hasSuffix("/v2/lookup") })
    let body = String(decoding: lookup.httpBody ?? Data(), as: UTF8.self)
    #expect(body.contains("client=venue-key"))
    #expect(body.contains("duration=353"))
    #expect(body.contains("fingerprint=AQAAS5LU%2B/x"))
}

@Test func anIdentityGoesOntoATimingFilesRecording() {
    let found = MediaRecording(title: "Defying Gravity", artist: "Idina Menzel", isrc: "USDW10310279",
                               musicbrainzRecordingId: "0b7f5c8f-1d55-4b8a-9b0e-6f0e7a3d4c21", fingerprint: "AQAA",
                               spotifyTrackIds: ["4cOdK2wGLETKBW3PvgPWqT"])
    let timingFiles = MediaRecording(title: "Defying Gravity", spotifyTrackIds: ["6pYzGDDgiOBvBqvZ0TUYnt"])
    let merged = found.merged(over: timingFiles)
    #expect(merged.musicbrainzRecordingId == "0b7f5c8f-1d55-4b8a-9b0e-6f0e7a3d4c21")
    #expect(merged.artist == "Idina Menzel")
    #expect(merged.spotifyTrackIds == ["6pYzGDDgiOBvBqvZ0TUYnt", "4cOdK2wGLETKBW3PvgPWqT"])
}
