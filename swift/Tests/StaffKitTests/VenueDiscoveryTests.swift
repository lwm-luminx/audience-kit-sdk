import Foundation
import Testing
import StaffKitServices

private func venue(point: String? = nil) throws -> VenueWorkspace {
    var payload: [String: Any] = ["id": "venue", "name": "Café Velvet",
                                "profile": ["address": "123 Main Street", "socialLinks": ["nodes": []]],
                                "locale": ["name": "Denver"], "upcomingEvents": ["upcoming": ["nodes": []]], "tickets": ["cover": ["canWorkDoor": true]]]
    if let point { payload["point"] = point }
    return try JSONDecoder().decode(VenueWorkspace.self, from: JSONSerialization.data(withJSONObject: payload))
}

@Test func venueSearchMatchesWordsAcrossNameAddressAndCity() throws {
    let place = try venue()
    #expect(place.matches(search: "  cafe DENVER  "))
    #expect(place.matches(search: "main velvet"))
    #expect(place.matches(search: "   "))
    #expect(!place.matches(search: "velvet boulder"))
}

@Test func venueCoordinatesReadLongitudeFirstAndRejectInvalidPoints() throws {
    let place = try venue(point: "SRID=4326;POINT (-104.99 39.74)")
    #expect(place.coordinate?.latitude == 39.74)
    #expect(place.coordinate?.longitude == -104.99)
    #expect(try venue().coordinate == nil)
    for invalid in ["POINT EMPTY", "POINT (200 39)", "POINT (0 91)", "POINT (nan 0)", "POINT )(", "LINESTRING (0 0, 1 1)"] {
        #expect(try venue(point: invalid).coordinate == nil)
    }
}
