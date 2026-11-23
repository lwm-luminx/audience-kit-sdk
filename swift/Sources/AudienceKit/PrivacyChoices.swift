import AudienceCore
import Foundation

// Privacy choices, per audience: what a member chooses about their data in this app's audience. Opting out of selling
// or sharing their personal information (CCPA/CPRA; a Global Privacy Control signal counts too) and of being counted
// in sponsors' viewer numbers are free, always offered and one switch each, the same either way. Where the audience
// sells one, a privacy pass turns off paid cards and every optional use of their data for a while: it's paid on the
// web, in the browser, so the apps offer it in US storefronts only, as with tips to read without ads. The API enforces
// every choice; the app only shows the switches. See the API's doc/PRIVACY_CHOICES.md.

/// A privacy choice the audience's apps show. Unknown keys from a newer API are left out.
public enum PrivacyChoiceKey: String, Codable, Sendable, CaseIterable {
    case saleShareOptOut = "SALE_SHARE_OPT_OUT"
    case adMeasurement = "AD_MEASUREMENT"
    case personalizedAds = "PERSONALIZED_ADS"
    case privacyPass = "PRIVACY_PASS"
}

/// What the audience offers: the choices to show, in order, and its privacy pass.
public struct PrivacyOffer: Sendable, Hashable {
    /// The switches to show, opting out of selling or sharing first. ``PrivacyChoiceKey/privacyPass`` means a pass is
    /// for sale (see ``PrivacyChoicesCopy/isPassOffered(_:storefrontCountryCode:)``).
    public let choices: [PrivacyChoiceKey]
    /// What a pass costs, in US cents; nil when none is for sale.
    public let passCents: Int?
    /// How many days one pass lasts.
    public let passDays: Int

    public init(choices: [PrivacyChoiceKey], passCents: Int? = nil, passDays: Int = 30) {
        self.choices = choices
        self.passCents = passCents
        self.passDays = passDays
    }

    /// When the API can't say: the opt-out of selling or sharing, which every audience offers.
    public static let minimum = PrivacyOffer(choices: [.saleShareOptOut, .adMeasurement])
}

/// What the member chose in this audience, and what's in force once a privacy pass is counted.
public struct PrivacyChoices: Codable, Sendable, Hashable {
    public enum OptOutSource: String, Codable, Sendable {
        case choice = "CHOICE"
        case globalPrivacyControl = "GLOBAL_PRIVACY_CONTROL"
    }

    /// Whether they opted out of selling or sharing their personal information.
    public let saleShareOptedOut: Bool
    public let saleShareOptedOutAt: Date?
    /// How they opted out; nil when they haven't.
    public let saleShareOptOutSource: OptOutSource?
    /// Their choice to be counted in sponsors' weekly viewer numbers. On unless turned off.
    public let adMeasurement: Bool
    /// Whether they're counted now (``adMeasurement`` and no privacy pass).
    public let countedInAdMeasurement: Bool
    /// Their agreement to ads based on their activity. Off unless turned on.
    public let personalizedAds: Bool
    /// Whether anything about them may be sold or shared for advertising. Nothing is today.
    public let mayShare: Bool
    /// When their privacy pass ends; nil when none is running.
    public let privacyPassUntil: Date?

    public init(saleShareOptedOut: Bool = false, saleShareOptedOutAt: Date? = nil,
                saleShareOptOutSource: OptOutSource? = nil, adMeasurement: Bool = true,
                countedInAdMeasurement: Bool = true, personalizedAds: Bool = false, mayShare: Bool = true,
                privacyPassUntil: Date? = nil)
    {
        self.saleShareOptedOut = saleShareOptedOut
        self.saleShareOptedOutAt = saleShareOptedOutAt
        self.saleShareOptOutSource = saleShareOptOutSource
        self.adMeasurement = adMeasurement
        self.countedInAdMeasurement = countedInAdMeasurement
        self.personalizedAds = personalizedAds
        self.mayShare = mayShare
        self.privacyPassUntil = privacyPassUntil
    }

    /// Before a member signs in, or when the API can't say: the defaults.
    public static let defaults = PrivacyChoices()

    public var hasPrivacyPass: Bool { privacyPassUntil != nil }

    /// Whether the switch for `key` is on. A privacy pass has no switch.
    public func isOn(_ key: PrivacyChoiceKey) -> Bool {
        switch key {
        case .saleShareOptOut: saleShareOptedOut
        case .adMeasurement: adMeasurement
        case .personalizedAds: personalizedAds
        case .privacyPass: hasPrivacyPass
        }
    }
}

/// A started privacy pass: open ``checkoutURL`` in the browser (not an in-app web view), then read
/// ``AudienceSession/privacy()`` again when they come back.
public struct PrivacyPassCheckout: Sendable, Hashable {
    public let passID: String
    /// Stripe Checkout, on AudienceKit's platform account. Good for an hour.
    public let checkoutURL: URL

    public init(passID: String, checkoutURL: URL) {
        self.passID = passID
        self.checkoutURL = checkoutURL
    }
}

/// The API's answer to ``AudienceSession/startPrivacyPass(returnURL:)`` had no checkout.
public struct PrivacyPassUnavailable: Error, Sendable {}

/// The words every app shows for its privacy choices (`PrivacyChoicesCopy` on Android too), so they say the same thing.
/// Not yet reviewed by a lawyer: see the API's doc/PRIVACY_CHOICES.md.
public enum PrivacyChoicesCopy {
    /// The settings row and screen title. CCPA's alternative opt-out link name, which covers selling, sharing and the
    /// other choices together.
    public static let title = "Your privacy choices"

    public static func intro(appName: String) -> String {
        """
        These choices are for \(appName) only. Turning something off is as easy as turning it on, and none of the \
        free choices ever costs anything.
        """
    }

    public static func label(_ key: PrivacyChoiceKey) -> String {
        switch key {
        case .saleShareOptOut: "Do not sell or share my personal information"
        case .adMeasurement: "Count me in sponsors' viewer numbers"
        case .personalizedAds: "Ads based on my activity"
        case .privacyPass: "Privacy pass"
        }
    }

    public static func detail(_ key: PrivacyChoiceKey, appName: String) -> String {
        switch key {
        case .saleShareOptOut:
            """
            \(appName) doesn't sell your personal information or share it for advertising. Turn this on and it never \
            will, whatever changes.
            """
        case .adMeasurement:
            """
            Sponsors only ever see how many different people saw their card each week, never who. Turn this off and \
            you aren't counted.
            """
        case .personalizedAds:
            """
            Off unless you turn it on. While it's off, ads are chosen only by the screen, the place and the night, \
            never by anything about you.
            """
        case .privacyPass:
            "No Promoted or Sponsored cards, and none of your data used for ads, for a while."
        }
    }

    /// Under the opt-out, when a Global Privacy Control signal turned it on.
    public static let fromGlobalPrivacyControl = "Turned on by your browser's Global Privacy Control signal."

    /// Whether to offer the pass in the storefront with `storefrontCountryCode` (StoreKit's
    /// `Storefront.current?.countryCode`): it's paid on the web, which the stores allow from US storefronts only.
    /// The website passes nil for `storefrontCountryCode` and `isWeb: true`.
    public static func isPassOffered(_ offer: PrivacyOffer, storefrontCountryCode: String?, isWeb: Bool = false)
        -> Bool
    {
        guard offer.choices.contains(.privacyPass), offer.passCents != nil else { return false }
        if isWeb { return true }
        guard let code = storefrontCountryCode?.uppercased() else { return false }
        return AdFreeTips.webCheckoutStorefronts.contains(code)
    }

    /// The button: "Go without ads for 30 days, $2.99".
    public static func passButton(cents: Int, days: Int) -> String {
        "Go without ads for \(days) days, \(AdFreeTips.money(cents))"
    }

    public static func passExplanation(days: Int) -> String {
        """
        For \(days) days you'll see no Promoted or Sponsored cards, and none of your data is used for ads or \
        counted for sponsors. You pay once, on the web; nothing renews. The free choices above stay free either way.
        """
    }

    public static func passRunning(until: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return "Your privacy pass runs until \(formatter.string(from: until)). Thanks for supporting this community."
    }

    public static let pending = "We're confirming your payment. Your pass starts as soon as it clears."
}

extension Queries {
    static let privacy = """
    query Privacy {
      privacyOffer { choices passCents passDays }
      me {
        privacy {
          saleShareOptedOut saleShareOptedOutAt saleShareOptOutSource adMeasurement countedInAdMeasurement
          personalizedAds mayShare privacyPassUntil
        }
      }
    }
    """

    static let updatePrivacyChoices = """
    mutation UpdatePrivacyChoices($saleShareOptOut: Boolean, $adMeasurement: Boolean, $personalizedAds: Boolean) {
      updatePrivacyChoices(input: { saleShareOptOut: $saleShareOptOut, adMeasurement: $adMeasurement,
                                    personalizedAds: $personalizedAds }) {
        privacy {
          saleShareOptedOut saleShareOptedOutAt saleShareOptOutSource adMeasurement countedInAdMeasurement
          personalizedAds mayShare privacyPassUntil
        }
      }
    }
    """

    static let startPrivacyPass = """
    mutation StartPrivacyPass($returnUrl: String) {
      startPrivacyPass(input: { returnUrl: $returnUrl }) { checkoutUrl passId }
    }
    """
}

struct PrivacyResponse: Decodable, Sendable {
    struct Offer: Decodable, Sendable {
        var choices: [String]
        var passCents: Int?
        var passDays: Int
    }

    struct Me: Decodable, Sendable { var privacy: PrivacyChoices? }

    var privacyOffer: Offer?
    var me: Me?
}

struct UpdatePrivacyChoicesResponse: Decodable, Sendable {
    struct Payload: Decodable, Sendable { var privacy: PrivacyChoices }
    var updatePrivacyChoices: Payload?
}

struct StartPrivacyPassResponse: Decodable, Sendable {
    struct Payload: Decodable, Sendable {
        var checkoutUrl: String?
        var passId: String?
    }

    var startPrivacyPass: Payload?
}

extension AudienceSession {
    /// What the audience offers and what the member chose. Signed out, the choices are the defaults.
    public func privacy() async throws -> (offer: PrivacyOffer, choices: PrivacyChoices) {
        let response = try await graphQL(Queries.privacy, operationName: "Privacy", as: PrivacyResponse.self,
                                         cachePolicy: .networkOnly)
        let offer = response.privacyOffer.map {
            PrivacyOffer(choices: $0.choices.compactMap(PrivacyChoiceKey.init(rawValue:)), passCents: $0.passCents,
                         passDays: $0.passDays)
        } ?? .minimum
        return (offer, response.me?.privacy ?? .defaults)
    }

    /// Changes the member's choices; each left nil stays as it is. Returns them as they now stand.
    @discardableResult
    public func updatePrivacyChoices(saleShareOptOut: Bool? = nil, adMeasurement: Bool? = nil,
                                     personalizedAds: Bool? = nil) async throws -> PrivacyChoices
    {
        let variables: [String: GraphQLValue] = [
            "saleShareOptOut": saleShareOptOut.map { .bool($0) } ?? .null,
            "adMeasurement": adMeasurement.map { .bool($0) } ?? .null,
            "personalizedAds": personalizedAds.map { .bool($0) } ?? .null,
        ]
        let response = try await graphQL(Queries.updatePrivacyChoices, variables: variables,
                                         operationName: "UpdatePrivacyChoices",
                                         as: UpdatePrivacyChoicesResponse.self)
        guard let privacy = response.updatePrivacyChoices?.privacy else { return .defaults }
        return privacy
    }

    /// Turns one switch on or off.
    @discardableResult
    public func setPrivacyChoice(_ key: PrivacyChoiceKey, on: Bool) async throws -> PrivacyChoices {
        switch key {
        case .saleShareOptOut: return try await updatePrivacyChoices(saleShareOptOut: on)
        case .adMeasurement: return try await updatePrivacyChoices(adMeasurement: on)
        case .personalizedAds: return try await updatePrivacyChoices(personalizedAds: on)
        case .privacyPass: return try await privacy().choices
        }
    }

    /// Starts paying for a privacy pass. `returnURL` is the app's own link (or a web address) Checkout comes back to.
    /// Offer it only where ``PrivacyChoicesCopy/isPassOffered(_:storefrontCountryCode:isWeb:)`` says so.
    public func startPrivacyPass(returnURL: String? = nil) async throws -> PrivacyPassCheckout {
        let variables: [String: GraphQLValue] = ["returnUrl": returnURL.map { .string($0) } ?? .null]
        let response = try await graphQL(Queries.startPrivacyPass, variables: variables,
                                         operationName: "StartPrivacyPass", as: StartPrivacyPassResponse.self)
        guard let payload = response.startPrivacyPass, let id = payload.passId,
              let string = payload.checkoutUrl, let url = URL(string: string)
        else { throw PrivacyPassUnavailable() }
        return PrivacyPassCheckout(passID: id, checkoutURL: url)
    }
}
