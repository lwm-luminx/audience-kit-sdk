import Foundation
import Testing
import StaffKitCore

@Test func pairLinksAreReadFromWhatTheTVShows() throws {
    let link = try #require(VenuePairingLink(url: URL(string: "https://audiencekit.com/pair/abcd-efgh")!))
    #expect(link.code == "ABCD-EFGH")
    #expect(VenuePairingLink(scanned: " https://www.audiencekit.com/pair/ABCDEFGH ")?.code == "ABCD-EFGH")
    #expect(VenuePairingLink(url: URL(string: "audiencekit-velvet://pair?code=abcd-efgh")!)?.code == "ABCD-EFGH")
    #expect(VenuePairingLink(url: URL(string: "audiencekit-velvet://venue?id=1")!) == nil)
    #expect(VenuePairingLink(scanned: "ABCD-EFGH-JKLM-NPQR") == nil)
    #expect(VenuePairingLink(scanned: "https://audiencekit.com/v/K7QX2M9PH4TD") == nil)
    #expect(VenuePairingLink(scanned: "https://example.com/pair/ABCD-EFGH") == nil)
    #expect(VenuePairingLink(scanned: "https://audiencekit.com/pair/ABC") == nil)
}

@Test func pairingsDecodeTheAPIAnswer() throws {
    let json = Data("""
    {"code":"ABCD-EFGH","url":"https://audiencekit.com/pair/ABCD-EFGH","poll_token":"t0k","expires_at":"2026-11-20T23:30:00.123Z","interval":3}
    """.utf8)
    let pairing = try JSONDecoder().decode(VenuePairing.self, from: json)
    #expect(pairing.code == "ABCD-EFGH")
    #expect(pairing.pollToken == "t0k")
    #expect(pairing.interval == 3)
    #expect(pairing.expiresAt.timeIntervalSince1970 > 1_795_000_000)
}
