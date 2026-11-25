import Foundation
import Testing
@testable import StaffKitServices

private let alertJSON = #"""
{"id":"s1","state":"OPEN","place":"DANCE_FLOOR","concerns":["BOTHERING"],"description":"Red cap","summary":"Dance floor · Someone's bothering them",
 "seen":false,"seenByMe":false,"acknowledgedByName":null,"acknowledgedAt":null,"escalatedAt":null,"remindedAt":null,"closedAt":null,
 "outcome":null,"staffNote":null,"supportSharedAt":null,"supportNote":null,"createdAt":"2026-10-23T03:15:00Z",
 "reporter":{"id":"u1","name":"Alex Rivera","avatarUrl":null},"event":null,
 "messages":[{"id":"m1","body":"By the speakers","fromStaff":false,"senderName":"Alex","createdAt":"2026-10-23T03:16:00Z"}]}
"""#

@Test func aStaffAlertDecodesWithItsReporterAndThread() throws {
    let alert = try JSONDecoder().decode(StaffSafetyAlert.self, from: Data(alertJSON.utf8))
    #expect(alert.isActive && alert.isOpen)
    #expect(alert.reporter?.name == "Alex Rivera")
    #expect(alert.messages.first?.fromStaff == false)
    #expect(StaffSafetyAlert.placeTitle(alert.place ?? "") == "Dance floor")
    #expect(StaffSafetyAlert.concernTitle("UNWELL") == "They don’t feel well")
    #expect(StaffSafetyAlert.outcomes.map(\.value) == ["SORTED", "REMOVED_SOMEONE", "NOT_FOUND", "NOT_NEEDED", "SEEMS_OFF",
                                                        "MISUSE"])
}

@Test func onlySafetyAlertPushesOpenAnAlert() {
    let push = SafetyAlertPush(userInfo: ["kind": "safety_alert", "alert_id": "s1", "venue_id": "v1", "audience_id": "a1"])
    #expect(push == SafetyAlertPush(alertID: "s1", venueID: "v1", audienceID: "a1"))
    #expect(SafetyAlertPush(userInfo: ["kind": "room_message", "room_id": "r1", "venue_id": "v1"]) == nil)
    #expect(SafetyAlertPush(userInfo: ["kind": "safety_alert", "venue_id": "v1"]) == nil)
}

@Test func aGeofencedShiftDecodesWhetherItHearsAlerts() throws {
    let fenced = try JSONDecoder().decode(SafetyShift.self, from: Data(#"{"onShift":true,"staffName":"Jo","geofenced":true,"hearing":false,"inside":null}"#.utf8))
    #expect(fenced.onShift && fenced.geofenced && !fenced.hearing && fenced.inside == nil)
    // An API from before geofences sends only onShift and staffName.
    let older = try JSONDecoder().decode(SafetyShift.self, from: Data(#"{"onShift":true,"staffName":null}"#.utf8))
    #expect(!older.geofenced && older.hearing)
    #expect(!SafetyShift(onShift: true, staffName: nil, geofenced: true, inside: false).hearing)
}

@Test func aShiftReadsAsAlwaysWhenAtTheVenueOrNever() {
    #expect(SafetyShift(onShift: true, staffName: nil).mode == .always)
    #expect(SafetyShift(onShift: true, staffName: nil, geofenced: true).mode == .atVenue)
    // Off is Never, whatever the geofence setting it had.
    #expect(SafetyShift(onShift: false, staffName: nil, geofenced: true).mode == .never)
    for mode in SafetyAlertMode.allCases {
        #expect(SafetyAlertMode(onShift: mode.onShift, geofenced: mode.geofenced) == mode)
    }
    #expect(SafetyAlertMode.atVenue.title(venueName: "Club Blue") == "When I’m at Club Blue")
}
