import Foundation

/// The platform and company credit every AudienceKit app shows at the foot of its About or Settings screen:
/// "Powered by AudienceKit", "A Love Wins Media product", AudienceKit's policy links and an invitation to bring
/// AudienceKit to your own venue or community. Love Wins Media is drawn in the pink-to-amber gradient that
/// audiencekit.com's band uses. `PlatformCreditFooter` (AudienceKitUI) draws it on iOS; Android's
/// `com.audiencekit.PlatformCredit` holds the same words, links and colours so both apps say the same thing.
///
/// Every link carries `utm_source` (the app's bundle ID), `utm_medium=app` and `utm_campaign` (which part of the
/// credit was tapped), so audiencekit.com's analytics show which apps send people. Nothing about the person goes
/// with it.
public enum PlatformCredit {
    public static let platformName = "AudienceKit"
    public static let companyName = "Love Wins Media"
    public static let companyLegalName = "Love Wins Media, Inc."
    public static let platformSite = URL(string: "https://audiencekit.com/")!
    public static let companySite = URL(string: "https://lovewins.media/")!

    /// "Powered by " before the platform name.
    public static let poweredByPrefix = "Powered by "
    /// "A " and " product" around the company name.
    public static let productPrefix = "A "
    public static let productSuffix = " product"
    /// The call to action under the credit.
    public static let callToAction = "Bring AudienceKit to your venue"

    public static var poweredBy: String { poweredByPrefix + platformName }
    public static var product: String { productPrefix + companyName + productSuffix }

    /// "© 2026 Love Wins Media, Inc."
    public static func copyright(year: Int = Calendar(identifier: .gregorian).component(.year, from: Date())) -> String {
        "© \(year) \(companyLegalName)"
    }

    /// The whole credit as one sentence, for VoiceOver and plain-text places (an email footer, say).
    public static var spoken: String { "\(poweredBy). \(product)." }

    /// AudienceKit's policy pages on audiencekit.com, in the order the footer shows them.
    public struct Policy: Equatable, Sendable {
        public let title: String
        public let path: String
    }

    public static let policies = [
        Policy(title: "Privacy", path: "privacy/"),
        Policy(title: "Terms", path: "terms/"),
        Policy(title: "Child safety", path: "child-safety/"),
        Policy(title: "Contact", path: "contact/"),
    ]

    /// A link to `path` on audiencekit.com, tagged with the app it came from and what was tapped.
    public static func platformURL(path: String = "", campaign: String = "credit",
                                   source: String? = Bundle.main.bundleIdentifier) -> URL {
        tagged(platformSite, path: path, campaign: campaign, source: source)
    }

    /// lovewins.media, tagged the same way.
    public static func companyURL(source: String? = Bundle.main.bundleIdentifier) -> URL {
        tagged(companySite, path: "", campaign: "credit", source: source)
    }

    /// The call to action's link: audiencekit.com's front page, campaign `venue_cta`.
    public static func callToActionURL(source: String? = Bundle.main.bundleIdentifier) -> URL {
        platformURL(campaign: "venue_cta", source: source)
    }

    public static func policyURL(_ policy: Policy, source: String? = Bundle.main.bundleIdentifier) -> URL {
        platformURL(path: policy.path, campaign: "policy", source: source)
    }

    /// The company name's gradient, start to end, as hex: pink to amber, darker on light backgrounds so it keeps
    /// contrast (the same stops as audiencekit.com's band).
    public static let gradientLight = ["#db2777", "#d97706"]
    public static let gradientDark = ["#f472b6", "#fbbf24"]

    private static func tagged(_ site: URL, path: String, campaign: String, source: String?) -> URL {
        var components = URLComponents(url: site.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if components.path.isEmpty { components.path = "/" }
        components.queryItems = [
            URLQueryItem(name: "utm_source", value: source?.isEmpty == false ? source : "audiencekit-app"),
            URLQueryItem(name: "utm_medium", value: "app"),
            URLQueryItem(name: "utm_campaign", value: campaign),
        ]
        return components.url ?? site
    }
}
