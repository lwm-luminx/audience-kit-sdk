import XCTest
@testable import StaffKitServices

final class VelvetScreenAdvertTests: XCTestCase {
    func testTXTRoundTrips() {
        let advert = VelvetScreenAdvert.Advert(name: "Bar TV", platform: "tvos", deviceID: "6F1C", displayID: "d-1",
                                               venueID: "venue-1", audienceID: "aud-1", appVersion: "1.12",
                                               build: "42", model: "AppleTV14,1")
        XCTAssertEqual(advert.txt, ["v": "1", "platform": "tvos", "device": "6F1C", "display": "d-1",
                                    "venue": "venue-1", "audience": "aud-1", "app": "1.12", "build": "42",
                                    "model": "AppleTV14,1"])
        XCTAssertEqual(VelvetScreenAdvert.Advert(name: "Bar TV", txt: advert.txt), advert)
        XCTAssertEqual(advert.screenKey, "d-1")
    }

    func testSignedOutTVOmitsMissingValues() {
        let advert = VelvetScreenAdvert.Advert(name: "TV", platform: "androidtv", deviceID: "abc", venueID: " ")
        XCTAssertEqual(advert.txt, ["v": "1", "platform": "androidtv", "device": "abc"])
        XCTAssertEqual(advert.screenKey, "abc")
        let read = VelvetScreenAdvert.Advert(name: "TV", txt: ["v": "1", "venue": "", "display": " "])
        XCTAssertNil(read.venueID)
        XCTAssertNil(read.displayID)
        XCTAssertNil(read.screenKey)
    }

    func testLongValuesFitATXTString() {
        let advert = VelvetScreenAdvert.Advert(name: "TV", model: String(repeating: "é", count: 300))
        let model = advert.txt["model"]!
        XCTAssertLessThanOrEqual(model.utf8.count + "model=".utf8.count, 255)
        XCTAssertEqual(model, String(repeating: "é", count: 124))
    }

    func testInstanceName() {
        XCTAssertEqual(VelvetScreenAdvert.instanceName("  Living Room  "), "Living Room")
        XCTAssertEqual(VelvetScreenAdvert.instanceName(""), "Velvet TV")
        XCTAssertEqual(VelvetScreenAdvert.instanceName(String(repeating: "é", count: 40)), String(repeating: "é", count: 31))
    }
}
