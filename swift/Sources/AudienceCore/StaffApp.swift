import Foundation

/// The AudienceKit staff apps: Focus for an audience's curators, Velvet for venues, Backstage for performers and
/// promoters. Every AudienceKit app links to them (Hot Mess's "Open in Velvet", AudienceKit's own cards about getting
/// one, Focus's invite codes), so their names, links and URL schemes live here once.
///
/// To tell whether one is installed on iOS, list each ``urlScheme`` under `LSApplicationQueriesSchemes` in the app's
/// Info.plist and use `AudienceKitUI`'s `StaffApp.isInstalled`.
public enum StaffApp: String, CaseIterable, Sendable, Hashable, Codable {
    case focus, velvet, backstage

    /// The name on the home screen.
    public var name: String {
        switch self {
        case .focus: "Focus"
        case .velvet: "Velvet"
        case .backstage: "Backstage"
        }
    }

    /// Who it's for, in a few words, under the name.
    public var tagline: String {
        switch self {
        case .focus: "Curate and moderate your audience"
        case .velvet: "Run the night at your venue"
        case .backstage: "Your nights, profile and tips"
        }
    }

    /// An SF Symbol for a row or button.
    public var systemImage: String {
        switch self {
        case .focus: "scope"
        case .velvet: "door.left.hand.open"
        case .backstage: "theatermasks"
        }
    }

    /// Whether it's still in beta (TestFlight and Play's open testing), so links say "Join the beta".
    public var isBeta: Bool { self == .velvet }

    /// The App Store Connect Apple ID of the production app.
    public var appStoreID: String {
        switch self {
        case .focus: "6821187977"
        case .velvet: "6820764256"
        case .backstage: "6821187736"
        }
    }

    /// The app's App Store page.
    public var appStoreURL: URL { URL(string: "https://apps.apple.com/app/id\(appStoreID)")! }

    /// Its Android package (the production build; Next builds add `.next`).
    public var androidPackage: String { "com.audiencekit.\(name)" }

    /// Its URL scheme, `audiencekit-velvet` and so on.
    public var urlScheme: String { "audiencekit-\(rawValue)" }

    /// Opens the app on its home screen.
    public var homeURL: URL { URL(string: "\(urlScheme)://")! }

    /// audiencekit.com's page for the app, which sends each phone to its store (or the beta). The link and QR code to
    /// share; `source` (an app's bundle ID, say) goes along as `utm_source`.
    public func downloadURL(source: String? = Bundle.main.bundleIdentifier, campaign: String = "staff_app") -> URL {
        PlatformCredit.platformURL(path: "apps/\(rawValue)/", campaign: campaign, source: source)
    }

    /// A button's words for the app: "Open in Velvet", or "Get Backstage" / "Join the Velvet beta" when the phone
    /// doesn't have it.
    public func linkTitle(installed: Bool) -> String {
        if installed { return "Open in \(name)" }
        return isBeta ? "Join the \(name) beta" : "Get \(name)"
    }

    /// The staff apps other than `app`, in the order the store copy lists them.
    public static func others(than app: StaffApp) -> [StaffApp] { allCases.filter { $0 != app } }

    /// Opens Velvet on a venue's workspace: `audiencekit-velvet://venue?id=<venue>&audience=<audience>`.
    public static func velvet(venueID: String, audienceID: String?) -> URL {
        StaffApp.velvet.link(host: "venue", id: venueID, audienceID: audienceID)
    }

    /// Opens Backstage on a person's page: `audiencekit-backstage://person?id=<person>&audience=<audience>`.
    public static func backstage(personID: String, audienceID: String?) -> URL {
        StaffApp.backstage.link(host: "person", id: personID, audienceID: audienceID)
    }

    func link(host: String, id: String, audienceID: String?) -> URL {
        var components = URLComponents()
        components.scheme = urlScheme
        components.host = host
        components.queryItems = [URLQueryItem(name: "id", value: id)]
            + (audienceID.map { [URLQueryItem(name: "audience", value: $0)] } ?? [])
        return components.url!
    }
}
