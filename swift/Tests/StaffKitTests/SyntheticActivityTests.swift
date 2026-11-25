import Foundation
import Testing
import StaffKitServices

@Test func syntheticBingoCallsMoreBallsAsTimeGoesOn() throws {
    let started = Date(timeIntervalSince1970: 1_800_000_000)
    let first = try #require(SyntheticActivity.games("bingo", now: started, started: started))
    let later = try #require(SyntheticActivity.games("bingo", now: started.addingTimeInterval(20), started: started))
    let done = try #require(SyntheticActivity.games("bingo", now: started.addingTimeInterval(3600), started: started))

    #expect(first.activity?.kind == VenueLiveActivity.bingo)
    #expect(first.followsActivity)
    #expect(first.bingo?.pattern == "Four corners")
    #expect(first.bingo?.calls.count == 12)
    #expect(later.bingo?.calls.count == 17)
    #expect(done.bingo?.calls.count == 40)
    #expect(first.bingo?.calls.first?.label == "B-7")
    // Every ball sits in its column and none comes out twice.
    let calls = try #require(done.bingo?.calls)
    #expect(Set(calls.map(\.number)).count == calls.count)
    #expect(calls.allSatisfy { ["B", "I", "N", "G", "O"][($0.number - 1) / 15] == $0.letter })
}

@Test func syntheticSingAlongIsAlreadyIntoTheSong() throws {
    let started = Date(timeIntervalSince1970: 1_800_000_000)
    let games = try #require(SyntheticActivity.games("sing_along", started: started))
    let song = try #require(games.activity?.song)

    #expect(games.activity?.kind == VenueLiveActivity.singAlong)
    #expect(games.bingo == nil)
    #expect(song.title == "Velvet Rope")
    #expect(song.artist == "The Review Room House Band")
    #expect(song.lines?.count == 16)
    #expect(song.lines?.map(\.time) == (0..<16).map { Double($0) * 4 })
    #expect(song.startedAt == ISO8601DateFormatter().string(from: started.addingTimeInterval(-3)))
}

@Test func syntheticNoneSetsNothingWhateverTheVenueRuns() throws {
    let games = try #require(SyntheticActivity.games("none"))

    #expect(games.followsActivity)
    #expect(games.activity == nil)
    #expect(games.bingo == nil)
    #expect(games.showing == .nothing)
}

@Test func syntheticActivityIgnoresOtherKinds() {
    #expect(SyntheticActivity.games("trivia") == nil)
    #expect(SyntheticActivity.games("") == nil)
}
