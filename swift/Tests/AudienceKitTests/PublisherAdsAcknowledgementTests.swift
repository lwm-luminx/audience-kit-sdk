import Foundation
import Testing
@testable import AudienceKit

struct PublisherAdsAcknowledgementTests {
    @Test func remembersEachPersonSeparately() throws {
        let defaults = try #require(UserDefaults(suiteName: "publisher-ads-\(UUID().uuidString)"))
        let store = PublisherAdsAcknowledgement(defaults: defaults, cloud: false)

        #expect(!store.isAcknowledged(by: "A1B2"))
        store.acknowledge(userID: "A1B2")
        #expect(store.isAcknowledged(by: "a1b2"))
        #expect(!store.isAcknowledged(by: "c3d4"))
        #expect(PublisherAdsAcknowledgement(defaults: defaults, cloud: false).isAcknowledged(by: "A1B2"))

        store.reset()
        #expect(!store.isAcknowledged(by: "A1B2"))
    }

    @Test func nobodySignedInNeverAcknowledges() throws {
        let defaults = try #require(UserDefaults(suiteName: "publisher-ads-\(UUID().uuidString)"))
        let store = PublisherAdsAcknowledgement(defaults: defaults, cloud: false)
        store.acknowledge(userID: nil)
        store.acknowledge(userID: " ")
        #expect(!store.isAcknowledged(by: nil))
        #expect(defaults.stringArray(forKey: PublisherAdsAcknowledgement.key) == nil)
    }

    @Test func copyNamesTheAppAndSaysWhoseAdsTheyAre() {
        let body = PublisherAdsCopy.body(appName: "Hot Mess")
        #expect(body.contains("Hot Mess takes no cut"))
        #expect(body.contains("keep paying writers"))
        #expect(body.contains("never shares your data with a publisher's advertisers"))
        #expect(body.contains("marked Sponsored"))
    }
}
