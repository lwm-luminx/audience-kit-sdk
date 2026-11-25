import Foundation
import Testing
@testable import StaffKitCore

@Suite struct StaffAppTests {
    @Test func eachAppLinksToItsAppStorePage() {
        #expect(StaffApp.velvet.appStoreURL.absoluteString == "https://apps.apple.com/app/id6820764256")
        #expect(Set(StaffApp.allCases.map(\.appStoreID)).count == StaffApp.allCases.count)
    }

    @Test func anAppListsOnlyTheOthers() {
        #expect(StaffApp.others(than: .focus) == [.velvet, .backstage])
        #expect(StaffApp.others(than: .backstage) == [.focus, .velvet])
    }
}
