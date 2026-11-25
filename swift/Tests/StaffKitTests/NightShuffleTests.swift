import Foundation
import Testing
@testable import StaffKitServices

// Velvet Display's own shuffle of a night's playlist, so what plays next is known.

private let songs = (1...12).map { PlaylistTrack(uri: "spotify:track:\($0)", title: "Song \($0)") }

@Test func aNightKeepsItsOrderAndNextWeekDiffers() {
    let calendar = Calendar(identifier: .gregorian)
    let tuesday = calendar.date(from: DateComponents(year: 2026, month: 11, day: 24, hour: 21))!
    let afterMidnight = calendar.date(from: DateComponents(year: 2026, month: 11, day: 25, hour: 1))!
    let nextWeek = calendar.date(from: DateComponents(year: 2026, month: 12, day: 1, hour: 21))!
    let seed = NightShuffle.seed(for: "event-1", on: tuesday, calendar: calendar)
    #expect(seed == NightShuffle.seed(for: "event-1", on: afterMidnight, calendar: calendar))
    let night = NightShuffle(tracks: songs, seed: seed)
    #expect(night.order == NightShuffle(tracks: songs, seed: seed).order)
    #expect(Set(night.order) == Set(songs))
    #expect(night.order != songs)
    #expect(night.order != NightShuffle(tracks: songs, seed: NightShuffle.seed(for: "event-1", on: nextWeek, calendar: calendar)).order)
}

@Test func upNextWrapsAndFollowsSkips() {
    var night = NightShuffle(tracks: songs + [songs[0]], seed: "x")
    #expect(night.order.count == 12)
    #expect(night.upNext().count == NightShuffle.upNextCount)
    #expect(night.upNext().first == night.order[1])
    for _ in 0..<11 { night.advance() }
    #expect(night.current == night.order[11])
    #expect(night.upNext(2) == [night.order[0], night.order[1]])
    night.back()
    #expect(night.index == 10)
    let third = night.order[3].uri
    let followed = night.follow(uri: third)
    #expect(followed)
    #expect(night.index == 3)
    let elsewhere = night.follow(uri: "spotify:track:elsewhere")
    #expect(!elsewhere)
    #expect(NightShuffle(tracks: [songs[0]], seed: "x").upNext().isEmpty)
}

/// The same order the API puts a night's songs in its lineup (NightPlaylistLineup.shuffled, audience_kit_api #781):
/// change both together.
@Test func matchesTheAPIsShuffle() {
    let tracks = (1...12).map { PlaylistTrack(uri: "\($0)", title: "\($0)") }
    let order = NightShuffle.shuffled(tracks, seed: "night|2026-11-20").map(\.uri)
    #expect(order == ["7", "4", "6", "2", "9", "3", "8", "12", "1", "10", "11", "5"])
}

@Test func takesTheOrderStaffSetInTonightsQueue() {
    var night = NightShuffle(tracks: songs, seed: "x")
    night.advance()
    let played = Array(night.order[...1])
    let later = night.order[5].uri, soon = night.order[2].uri
    night.reorder(coming: [later, "spotify:track:elsewhere", soon, later])
    #expect(Array(night.order[...1]) == played)
    #expect(night.order[2].uri == later)
    #expect(night.order[3].uri == soon)
    #expect(Set(night.order) == Set(songs))
    #expect(night.order.count == songs.count)
    #expect(night.upNext(1).first?.uri == later)
}
