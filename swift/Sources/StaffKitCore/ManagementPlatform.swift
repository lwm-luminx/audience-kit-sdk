import AudienceCore
import Foundation

/// Where AudienceKit's own management apps (Focus, Velvet, Backstage) sign in, for each environment: the API, the
/// platform console host that names the platform to it, and the platform Facebook app with its Login for Business
/// configuration. Staging builds use the next preview, which runs new API code against production data.
public struct ManagementPlatform: Sendable, Hashable {
    public let baseURL: URL
    public let host: String
    public let facebookAppID: String
    public let facebookLoginConfigurationID: String
    /// The Login for Business configuration that asks for Page posting permissions (pages_show_list,
    /// pages_read_engagement, pages_manage_posts, instagram_basic, instagram_content_publish), for linking a listing's
    /// Facebook Page and Instagram account (``SocialAccountsClient``): the API's `facebook.publish_login_config`. Nil
    /// where the platform's Facebook app has none yet, and linking isn't offered there.
    public let facebookPublishLoginConfigurationID: String?

    public init(baseURL: URL, host: String, facebookAppID: String, facebookLoginConfigurationID: String,
                facebookPublishLoginConfigurationID: String? = nil) {
        self.baseURL = baseURL
        self.host = host
        self.facebookAppID = facebookAppID
        self.facebookLoginConfigurationID = facebookLoginConfigurationID
        self.facebookPublishLoginConfigurationID = facebookPublishLoginConfigurationID
    }

    public static let production = ManagementPlatform(
        baseURL: AudienceKitSDK.productionBaseURL, host: "admin.audiencekit.com",
        facebookAppID: "713525445368431", facebookLoginConfigurationID: "4085560021745660",
        facebookPublishLoginConfigurationID: "1658512575778916"
    )

    public static let next = ManagementPlatform(
        baseURL: URL(string: "https://api.next.audiencekit.com")!, host: "admin.next.audiencekit.com",
        facebookAppID: "915436455177328", facebookLoginConfigurationID: "1489636529653307",
        facebookPublishLoginConfigurationID: "1160883476308008"
    )

    /// Whether listings can link their Facebook Page and Instagram account for posting on this platform.
    public var canLinkSocialAccounts: Bool { facebookPublishLoginConfigurationID != nil }

    /// An environment this SDK doesn't know (``AudienceKitEnvironment/unknown(_:)``) signs in on the production
    /// platform: no staff build ships with one.
    /// The APIs whose sign-ins this one takes: next takes production's (its `TRUSTED_API_ORIGIN`), so a production
    /// session keeps working when an app switches to Next.
    public var trustedCredentialOrigins: [URL] { self == .next ? [Self.production.baseURL] : [] }

    public static func `for`(_ environment: AudienceKitEnvironment) -> ManagementPlatform {
        switch environment {
        case .staging: .next
        default: .production // production and unknown; `default` also covers cases a newer SDK adds
        }
    }
}
