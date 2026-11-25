import XCTest
@testable import StaffKitServices

final class KaraFunStreamTests: XCTestCase {
    private let url = URL(string: "http://192.168.1.20:5123/live.m3u8")!

    func testTXTRoundTrips() {
        let advert = KaraFunStream.Advert(name: "M4", venueID: "venue-1", url: url, showing: true)
        XCTAssertEqual(advert.txt, ["on": "1", "venue": "venue-1", "url": url.absoluteString])
        XCTAssertEqual(KaraFunStream.Advert(name: "M4", txt: advert.txt), advert)
    }

    func testMissingAndEmptyValues() {
        let advert = KaraFunStream.Advert(name: "M4", txt: ["venue": " ", "on": "0"])
        XCTAssertNil(advert.venueID)
        XCTAssertNil(advert.url)
        XCTAssertFalse(advert.showing)
    }

    func testPicksOwnVenueShowingKaraFun() {
        let other = KaraFunStream.Advert(name: "A", venueID: "venue-2", url: url, showing: true)
        let idle = KaraFunStream.Advert(name: "B", venueID: "venue-1", url: url, showing: false)
        let own = KaraFunStream.Advert(name: "C", venueID: "venue-1", url: url, showing: true)
        let unknown = KaraFunStream.Advert(name: "D", venueID: nil, url: url, showing: true)
        XCTAssertEqual(KaraFunStream.pick([other, idle, own, unknown], venueID: "venue-1"), own)
        XCTAssertEqual(KaraFunStream.pick([other, idle, unknown], venueID: "venue-1"), unknown)
        XCTAssertNil(KaraFunStream.pick([other, idle], venueID: "venue-1"))
        XCTAssertNil(KaraFunStream.pick([KaraFunStream.Advert(name: "E", venueID: "venue-1", url: nil, showing: true)],
                                        venueID: "venue-1"))
    }

    func testURL() {
        XCTAssertEqual(KaraFunStream.url(host: "192.168.1.20", port: 5123), url)
    }
}
