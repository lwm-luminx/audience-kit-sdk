@testable import AudienceCore
import Foundation
import Testing

struct PlatformCreditTests {
    @Test func creditWords() {
        #expect(PlatformCredit.poweredBy == "Powered by AudienceKit")
        #expect(PlatformCredit.product == "A Love Wins Media product")
        #expect(PlatformCredit.spoken == "Powered by AudienceKit. A Love Wins Media product.")
        #expect(PlatformCredit.copyright(year: 2026) == "© 2026 Love Wins Media, Inc.")
        #expect(PlatformCredit.policies.map(\.title) == ["Privacy", "Terms", "Child safety", "Contact"])
    }

    @Test func creditLinksAreTagged() {
        #expect(PlatformCredit.policyURL(PlatformCredit.policies[0], source: "com.hotmess").absoluteString
            == "https://audiencekit.com/privacy/?utm_source=com.hotmess&utm_medium=app&utm_campaign=policy")
        #expect(PlatformCredit.companyURL(source: nil).absoluteString
            == "https://lovewins.media/?utm_source=audiencekit-app&utm_medium=app&utm_campaign=credit")
        #expect(PlatformCredit.callToActionURL(source: "").absoluteString
            == "https://audiencekit.com/?utm_source=audiencekit-app&utm_medium=app&utm_campaign=venue_cta")
    }

    @Test func staffAppLinksAndWords() {
        #expect(StaffApp.velvet(venueID: "v-1", audienceID: "a-1").absoluteString
            == "audiencekit-velvet://venue?id=v-1&audience=a-1")
        #expect(StaffApp.backstage(personID: "p-1", audienceID: nil).absoluteString
            == "audiencekit-backstage://person?id=p-1")
        #expect(StaffApp.velvet.homeURL.absoluteString == "audiencekit-velvet://")
        #expect(StaffApp.backstage.androidPackage == "com.audiencekit.Backstage")
        #expect(StaffApp.velvet.linkTitle(installed: true) == "Open in Velvet")
        #expect(StaffApp.velvet.linkTitle(installed: false) == "Join the Velvet beta")
        #expect(StaffApp.backstage.linkTitle(installed: false) == "Get Backstage")
        #expect(StaffApp.others(than: .focus) == [.velvet, .backstage])
        #expect(StaffApp.velvet.downloadURL(source: "com.hotmess").absoluteString
            == "https://audiencekit.com/apps/velvet/?utm_source=com.hotmess&utm_medium=app&utm_campaign=staff_app")
        #expect(StaffApp.allCases.allSatisfy { !$0.name.isEmpty && !$0.tagline.isEmpty && !$0.systemImage.isEmpty })
        #expect(StaffApp.allCases.allSatisfy { $0.appStoreURL.absoluteString.hasPrefix("https://apps.apple.com/app/id") })
    }
}
