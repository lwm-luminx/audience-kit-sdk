import Foundation
import Testing
@testable import StaffKitServices

// The sing-along caption cases shared with Velvet on Google TV's Kotlin port (core/test-cases/lyrics.json,
// VelvetTvLiveTest.kt): the syllabifier and the estimated syllable timing must split and time lyrics the same way on
// both, so a song looks the same on an Apple TV and a Google TV.

private struct LyricCases: Decodable {
    struct SyllableCase: Decodable { let line: String; let syllables: [String] }
    struct TimedLine: Decodable { let time: Double; let text: String }
    struct Syllable: Decodable { let text: String; let start: Double; let end: Double }
    struct Line: Decodable { let start: Double; let end: Double; let syllables: [Syllable] }
    struct EstimatedCase: Decodable {
        let lines: [TimedLine]
        let duration: Double?
        let breaksDuration: Double?
        let expected: [Line]
        let withBreaks: [Line]
    }

    let syllables: [SyllableCase]
    let estimated: [EstimatedCase]

    static func load() throws -> LyricCases {
        // swift/Tests/ManagementKitTests/this file -> the repository's root.
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0..<4 { root.deleteLastPathComponent() }
        let data = try Data(contentsOf: root.appendingPathComponent("core/test-cases/lyrics.json"))
        return try JSONDecoder().decode(LyricCases.self, from: data)
    }
}

private func expectSame(_ actual: SyllableLyrics, _ expected: [LyricCases.Line], _ label: String) {
    #expect(actual.lines.count == expected.count, "\(label): line count")
    for (line, want) in zip(actual.lines, expected) {
        #expect(abs(line.start - want.start) < 1e-6 && abs(line.end - want.end) < 1e-6,
                "\(label): \(line.start)-\(line.end), wanted \(want.start)-\(want.end)")
        #expect(line.syllables.map(\.text) == want.syllables.map(\.text), "\(label)")
        for (syllable, wanted) in zip(line.syllables, want.syllables) {
            #expect(abs(syllable.start - wanted.start) < 1e-6 && abs(syllable.end - wanted.end) < 1e-6,
                    "\(label): \(syllable.text)")
        }
    }
}

@Test func syllablesMatchTheSharedCases() throws {
    for item in try LyricCases.load().syllables {
        #expect(Syllabifier.syllables(item.line) == item.syllables, "\(item.line)")
    }
}

@Test func estimatedTimingMatchesTheSharedCases() throws {
    for (index, item) in try LyricCases.load().estimated.enumerated() {
        let lyrics = SyncedLyrics(lines: item.lines.map { SyncedLyrics.Line(time: $0.time, text: $0.text) })
        let estimated = SyllableLyrics.estimated(from: lyrics, duration: item.duration)
        expectSame(estimated, item.expected, "case \(index)")
        expectSame(estimated.withBreaks(duration: item.breaksDuration), item.withBreaks, "case \(index) with breaks")
    }
}
