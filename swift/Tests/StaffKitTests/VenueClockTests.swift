import Foundation
import Testing
import StaffKitServices

// The venue's clock (VenueClock.swift), shared by Velvet and the marquee on the iPad, the Mac and a TV.

private func venue(zone: String?, night: String? = nil) throws -> VenueWorkspace {
    var cover: [String: Any] = ["canWorkDoor": true]
    if let zone { cover["timeZone"] = zone }
    if let night { cover["door"] = ["night": night, "paidCount": 0, "checkedInCount": 0] }
    let payload: [String: Any] = ["id": "venue", "name": "Velvet", "locale": ["name": "Denver"], "tickets": ["cover": cover]]
    return try JSONDecoder().decode(VenueWorkspace.self, from: JSONSerialization.data(withJSONObject: payload))
}

@Test func venueClockReadsTimesAtTheVenueNotOnTheDevice() throws {
    let denver = try venue(zone: "America/Denver")
    #expect(denver.zone.identifier == "America/Denver")
    let nine = try #require(parseInstant("2026-10-11T03:00:00Z"))
    #expect(venueTime(nine, in: denver.zone).contains("9"))
    // 03:00 UTC on the 11th is 9 PM on the 10th in Denver; the day and month order follows the device's locale.
    let date = venueDate("2026-10-11T03:00:00Z", in: denver.zone)
    #expect(date.contains("10") && !date.contains("11"))
    #expect(venueDate("soon", in: denver.zone) == "soon")
    #expect(try venue(zone: nil).zone == .current)
}

@Test func tonightRunsFromSixInTheMorningOnTheDoorsNight() throws {
    let place = try venue(zone: "America/Denver", night: "2026-10-10")
    let tonight = place.tonight
    #expect(tonight.start == parseInstant("2026-10-10T12:00:00Z"))
    #expect(tonight.duration == 24 * 3600)
}
