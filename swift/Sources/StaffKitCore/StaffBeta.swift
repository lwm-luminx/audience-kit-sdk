import AudienceCore
import Foundation

/// One bundle ID per staff app: a TestFlight install of a beta build runs on the next platform, and can switch.
///
/// Xcode Cloud archives `next`, from its Next / TestFlight workflows, as a beta (`STAFF_BETA_SERVER = next`, Info.plist
/// `StaffBetaServer`); every other archive is a production build (ci_scripts/ci_pre_xcodebuild.sh, which also fails a
/// release workflow that would make a beta). When TestFlight installed a beta (a sandbox receipt), the app starts on
/// that server, shows the Server picker in its settings and wears a ribboned icon. Production builds, and anything from
/// the App Store, run on production. App Review installs into the same sandbox as TestFlight, which is why a beta must
/// never be submitted. Xcode installs have a sandbox receipt too, so a Debug run is a beta only with `STAFF_BETA_SERVER` set
/// in a Local.xcconfig. AudienceKit super admins get the picker in any install (``switchAllowedKey``).
public enum StaffBeta {
    /// The two platforms a beta can sign in to.
    public enum Server: String, CaseIterable, Sendable, Hashable {
        case next, production

        /// The environment the apps and ``ManagementPlatform/for(_:)`` read: next is the staging environment.
        public var environment: AudienceKitEnvironment { self == .next ? .staging : .production }

        public var title: String { self == .next ? "Next" : "Production" }
    }

    /// Where a beta's pick is kept: the staff apps' shared app group, so Focus, Velvet, Backstage and Arbiter on a
    /// device follow one choice (each server keeps its own shared sign-in, ``StaffKeychain/service(for:)``).
    public static let defaultsKey = "StaffAPIServer"

    /// Set once an AudienceKit super admin signed in on this device (the API's `me.canSwitchServer`): any install,
    /// App Store ones included, then offers the Server picker and runs on its pick.
    public static let switchAllowedKey = "StaffServerSwitchAllowed"

    /// Whether this install is a TestFlight beta (see the type's description).
    public static let isBeta = betaServer(bundle: .main) != nil

    /// The server this install runs on when it may switch (a beta, or a super admin's install): the pick from
    /// settings, else the beta's default, else production. `nil` for everyone else's App Store installs, main builds
    /// and Xcode runs.
    public static let current: Server? = server(bundle: .main, defaults: defaults)

    /// ``current`` for a given bundle and store, for tests.
    public static func server(bundle: Bundle, defaults: UserDefaults?) -> Server? {
        let beta = betaServer(bundle: bundle)
        guard beta != nil || defaults?.bool(forKey: switchAllowedKey) == true else { return nil }
        return defaults?.string(forKey: defaultsKey).flatMap(Server.init(rawValue:)) ?? beta ?? .production
    }

    private static func betaServer(bundle: Bundle) -> Server? {
        guard let beta = (bundle.object(forInfoDictionaryKey: "StaffBetaServer") as? String).flatMap(Server.init(rawValue:)),
              isSandboxInstall(bundle) else { return nil }
        return beta
    }

    /// Remembers what the API said about the signed-in person (`me.canSwitchServer`). Someone else signing in takes
    /// the picker away again, and the install goes back to production from its next launch.
    public static func remember(canSwitchServer: Bool) {
        defaults?.set(canSwitchServer, forKey: switchAllowedKey)
    }

    /// The store ``defaultsKey`` and ``switchAllowedKey`` live in, for views that follow them.
    public static var sharedDefaults: UserDefaults? { defaults }

    /// Whether TestFlight (or Xcode) installed the bundle: its receipt is a sandbox one. Read synchronously, because
    /// the platform is chosen before anything else runs; StoreKit's `AppTransaction` is async. A Mac app's receipt
    /// has the same name from TestFlight and the App Store (and a local build has none), so on the Mac (Arbiter) the
    /// build's key alone decides: beta archives are internal-only and never go to App Review.
    static func isSandboxInstall(_ bundle: Bundle) -> Bool {
        #if os(macOS)
        true
        #elseif canImport(Darwin)
        bundle.appStoreReceiptURL?.lastPathComponent == "sandboxReceipt"
        #else
        false
        #endif
    }

    /// Saves a beta's pick; it applies from the next launch.
    public static func choose(_ server: Server) {
        defaults?.set(server.rawValue, forKey: defaultsKey)
    }

    /// The icon an install wears: `AppIconNext` (the Next icon with a NEXT ribbon) on next, and for a beta
    /// `AppIconBeta` (the production icon with a BETA ribbon) on production; `nil`, the primary icon, for everything
    /// else, a super admin's App Store install on production included.
    public static func alternateIconName(for server: Server?, beta: Bool = isBeta) -> String? {
        switch server {
        case .next: "AppIconNext"
        case .production: beta ? "AppIconBeta" : nil
        case nil: nil
        }
    }

    private static var defaults: UserDefaults? { UserDefaults(suiteName: StaffKeychain.accessGroup) }
}
