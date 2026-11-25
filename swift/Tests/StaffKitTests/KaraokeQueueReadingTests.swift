import Foundation
import Testing
import AudienceCore
import AudienceKit
import StaffKitServices
import StaffKitCore

private typealias Line = KaraokeQueueText.Line

/// A line of text in KaraFun's side panel, which starts at x 0.7; rows are 0.02 tall.
private func line(_ text: String, x: Double = 0.72, y: Double, width: Double = 0.15) -> Line {
    Line(text: text, x: x, y: y, width: width, height: 0.02)
}

@Test func readsTurnsUnderTheQueueHeading() {
    let lines = [
        line("Now playing", x: 0.05, y: 0.05),
        line("Bohemian Rhapsody", x: 0.05, y: 0.08, width: 0.3),
        line("Queue (3)", y: 0.10),
        line("Dancing Queen", y: 0.15), line("Dalton", x: 0.9, y: 0.15, width: 0.06), line("ABBA", y: 0.172),
        line("3:51", x: 0.95, y: 0.172, width: 0.03),
        line("2. Jolene", y: 0.22), line("Sequoia", x: 0.9, y: 0.22, width: 0.06), line("Dolly Parton", y: 0.242),
        line("Toxic - Britney Spears", y: 0.29),
    ]
    let turns = KaraokeQueueText.parse(lines: lines)
    #expect(turns == [
        KaraokeQueueTurn(singer: "Dalton", title: "Dancing Queen", artist: "ABBA"),
        KaraokeQueueTurn(singer: "Sequoia", title: "Jolene", artist: "Dolly Parton"),
        KaraokeQueueTurn(singer: nil, title: "Toxic", artist: "Britney Spears"),
    ])
}

@Test func noHeadingMeansThePanelIsntShowing() {
    #expect(KaraokeQueueText.parse(lines: [line("Dancing Queen", y: 0.2)]) == nil)
    #expect(KaraokeQueueText.parse(lines: [line("Up next", y: 0.1)]) == [])
}

@Test func aByLineNamesTheSinger() {
    let turns = KaraokeQueueText.parse(lines: [
        line("Up next", y: 0.1), line("Total Eclipse of the Heart", y: 0.15), line("Bonnie Tyler", y: 0.172),
        line("by Dalton", y: 0.194),
    ])
    #expect(turns == [KaraokeQueueTurn(singer: "Dalton", title: "Total Eclipse of the Heart", artist: "Bonnie Tyler")])
}

@Test func linesLeftOfThePanelAreIgnored() {
    let turns = KaraokeQueueText.parse(lines: [
        line("Queue", y: 0.1), line("Lyrics on the left", x: 0.1, y: 0.15, width: 0.4), line("Jolene", y: 0.15),
    ])
    #expect(turns == [KaraokeQueueTurn(title: "Jolene")])
}

@Test func headingsAndNoiseAreRecognized() {
    #expect(KaraokeQueueText.isHeading("Queue"))
    #expect(KaraokeQueueText.isHeading("Queue (12)"))
    #expect(KaraokeQueueText.isHeading("UP NEXT"))
    #expect(!KaraokeQueueText.isHeading("Queen"))
}

@Test func accessibilityRowsBecomeTurns() {
    let turns = KaraokeQueueText.turns(rows: [
        ["1", "Dancing Queen", "ABBA", "Dalton", "3:51"],
        ["Jolene", "Dolly Parton"],
        ["Queue"],
        ["Toxic", "Britney Spears", "Singer: Sequoia"],
    ])
    #expect(turns == [
        KaraokeQueueTurn(singer: "Dalton", title: "Dancing Queen", artist: "ABBA"),
        KaraokeQueueTurn(title: "Jolene", artist: "Dolly Parton"),
        KaraokeQueueTurn(singer: "Sequoia", title: "Toxic", artist: "Britney Spears"),
    ])
}

@Test func reportsTheQueueToTheAPI() async throws {
    let stub = Stub { _ in
        .json(status: 200, body: #"{"data":{"reportKaraokeQueue":{"queue":[{"singer":"Dalton","title":"Jolene","artist":null}]}}}"#)
    }
    let session = AudienceManagementSession(baseURL: stub.baseURL, credentialStore: InMemoryCredentialStore(credential: makeCredential(audienceID: "audience", on: stub.baseURL)), session: stub.session)
    let queue = try await VenueManagementClient(session: session)
        .reportKaraokeQueue([KaraokeQueueTurn(singer: "Dalton", title: "Jolene")], source: "karafun-mac-text")
    #expect(queue == [KaraokeQueueTurn(singer: "Dalton", title: "Jolene")])
    let body = try #require(stub.requests.last).jsonBody()
    let variables = try #require(body["variables"] as? [String: Any])
    #expect(variables["source"] as? String == "karafun-mac-text")
    let entries = try #require(variables["entries"] as? [[String: Any]])
    #expect(entries.first?["title"] as? String == "Jolene")
    #expect(entries.first?["singer"] as? String == "Dalton")
    #expect(entries.first?["artist"] == nil)
}

@Test func readsTheVenuesKaraokeQueue() async throws {
    let stub = Stub { _ in
        .json(status: 200, body: #"{"data":{"venues":{"venue":{"karaoke":{"tonight":true,"providerName":"KaraFun","queue":[{"singer":"Dalton","title":"Jolene","artist":"Dolly Parton"}]}}}}}"#)
    }
    let session = AudienceManagementSession(baseURL: stub.baseURL, credentialStore: InMemoryCredentialStore(credential: makeCredential(audienceID: "audience", on: stub.baseURL)), session: stub.session)
    let queue = try #require(try await VenueManagementClient(session: session).karaokeQueue(venueID: "venue"))
    #expect(queue.turns == [KaraokeQueueTurn(singer: "Dalton", title: "Jolene", artist: "Dolly Parton")])
    #expect(VenueKaraokeQueue(tonight: false, queue: queue.queue).turns.isEmpty)
}
