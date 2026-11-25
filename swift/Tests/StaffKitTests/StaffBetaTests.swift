import Foundation
import Testing
@testable import StaffKitCore

@Suite struct StaffBetaTests {
    private func store() -> UserDefaults {
        let name = "StaffBetaTests.\(UUID().uuidString)"
        return UserDefaults(suiteName: name)!
    }

    @Test func aSuperAdminsInstallRunsOnItsPick() {
        let defaults = store()
        // The test bundle isn't a beta: no StaffBetaServer key.
        #expect(StaffBeta.server(bundle: .main, defaults: defaults) == nil)

        defaults.set(true, forKey: StaffBeta.switchAllowedKey)
        #expect(StaffBeta.server(bundle: .main, defaults: defaults) == .production)

        defaults.set("next", forKey: StaffBeta.defaultsKey)
        #expect(StaffBeta.server(bundle: .main, defaults: defaults) == .next)

        defaults.set(false, forKey: StaffBeta.switchAllowedKey)
        #expect(StaffBeta.server(bundle: .main, defaults: defaults) == nil)
    }

    @Test func onlyABetaWearsTheBetaRibbonOnProduction() {
        #expect(StaffBeta.alternateIconName(for: .next, beta: false) == "AppIconNext")
        #expect(StaffBeta.alternateIconName(for: .production, beta: true) == "AppIconBeta")
        #expect(StaffBeta.alternateIconName(for: .production, beta: false) == nil)
        #expect(StaffBeta.alternateIconName(for: nil, beta: true) == nil)
    }
}
