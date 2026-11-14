import AudienceCore
import Foundation

// Tip to read without ads: a reader tips a Soapbox publication, all of the tip goes to the publisher (the app takes
// nothing, as with performers' tips), and a big enough tip reads that publication without ads for a while. Because
// the ads going away ties the tip to content in the app, the stores don't count it as a gift, so it can't use the
// in-app payment sheet: the reader pays on the web, in their browser, and the apps offer it in US storefronts only.
// See the API's doc/SOAPBOX.md, "Tip to read without ads".

/// A started tip to a publication: open ``checkoutURL`` in the reader's browser (not an in-app web view), then call
/// ``AudienceSession/confirmTip(id:)`` when they come back to the app.
public struct AdFreeTipCheckout: Sendable, Hashable {
    public let tipID: String
    /// The web checkout, on the publisher's own Stripe account. Good for two hours.
    public let checkoutURL: URL

    public init(tipID: String, checkoutURL: URL) {
        self.tipID = tipID
        self.checkoutURL = checkoutURL
    }
}

/// Where a tip stands after ``AudienceSession/confirmTip(id:)``.
public struct TipConfirmation: Codable, Sendable, Hashable {
    public enum Status: String, Codable, Sendable {
        case pending = "PENDING"
        case paid = "PAID"
        case failed = "FAILED"
        case canceled = "CANCELED"
        case refunded = "REFUNDED"
        case disputed = "DISPUTED"
    }

    public let id: String
    public let status: Status
    /// When the time reading its publication without ads that it gave ends; nil when it gave none.
    public let readsAdFreeUntil: Date?

    public init(id: String, status: Status, readsAdFreeUntil: Date? = nil) {
        self.id = id
        self.status = status
        self.readsAdFreeUntil = readsAdFreeUntil
    }

    public var isPaid: Bool { status == .paid }
}

/// When the apps may offer tip to read without ads, and the words for it (`AdFreeTips` on Android too).
public enum AdFreeTips {
    /// Storefronts where the apps may link out to a web checkout: the United States only, for now. StoreKit gives
    /// alpha-3 codes ("USA"), Play's billing config alpha-2 ("US"); both are accepted.
    public static let webCheckoutStorefronts: Set<String> = ["USA", "US"]

    /// Whether to offer it for `publication` in the storefront with `storefrontCountryCode` (StoreKit's
    /// `Storefront.current?.countryCode`). False when the storefront is unknown.
    public static func isOffered(adFreeOffered: Bool?, storefrontCountryCode: String?) -> Bool {
        guard adFreeOffered == true, let code = storefrontCountryCode?.uppercased() else { return false }
        return webCheckoutStorefronts.contains(code)
    }

    public static func isOffered(_ publication: Publication, storefrontCountryCode: String?) -> Bool {
        isOffered(adFreeOffered: publication.adFreeOffered, storefrontCountryCode: storefrontCountryCode)
    }

    public static func isOffered(_ publication: PublicationSummary, storefrontCountryCode: String?) -> Bool {
        isOffered(adFreeOffered: publication.adFreeOffered, storefrontCountryCode: storefrontCountryCode)
    }

    /// The button: "Tip QSaltLake to read without ads".
    public static func button(publicationName: String) -> String { "Tip \(publicationName) to read without ads" }

    /// Under the button, before the reader leaves for the checkout.
    public static func explanation(publicationName: String, tipCents: Int, days: Int) -> String {
        """
        A tip of \(money(tipCents)) or more goes straight to \(publicationName), all of it: we take no cut. In \
        return you'll read \(publicationName) here without ads for \(days) days. You'll pay on the web, in your \
        browser.
        """
    }

    public static let continueToCheckout = "Continue to checkout"
    public static let pending = "We're confirming your tip. Ads go away as soon as it clears."
    public static let notPaid = "Your tip wasn't paid, so nothing changed."

    /// Shown where the ads would be, once a reader reads the publication without ads.
    public static func thanks(publicationName: String, until: Date?) -> String {
        guard let until else { return "Thanks for supporting \(publicationName). No ads here for you." }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        let date = formatter.string(from: until)
        return "Thanks for supporting \(publicationName). No ads here for you until \(date)."
    }

    static func money(_ cents: Int) -> String {
        cents % 100 == 0 ? "$\(cents / 100)" : String(format: "$%d.%02d", cents / 100, cents % 100)
    }
}

/// The API's answer to ``AudienceSession/startAdFreeTip(publicationID:amountCents:note:showFirstName:)`` had no web
/// checkout: the publication can't take tips here yet.
public struct AdFreeTipUnavailable: Error, Sendable {}

extension Queries {
    static let startAdFreeTip = """
    mutation StartAdFreeTip($publicationId: ID!, $amountCents: Int!, $note: String, $showFirstName: Boolean) {
      startTip(input: { publicationId: $publicationId, amountCents: $amountCents, note: $note,
                        showFirstName: $showFirstName }) {
        checkoutUrl
        tip { id }
      }
    }
    """

    static let confirmTip = """
    mutation ConfirmTip($tipId: ID!) {
      confirmTip(input: { tipId: $tipId }) { tip { id status readsAdFreeUntil } }
    }
    """
}

struct StartAdFreeTipResponse: Decodable, Sendable {
    struct Payload: Decodable, Sendable {
        struct Tip: Decodable, Sendable { var id: String }
        var checkoutUrl: String?
        var tip: Tip?
    }

    var startTip: Payload?
}

struct ConfirmTipResponse: Decodable, Sendable {
    struct Payload: Decodable, Sendable { var tip: TipConfirmation? }
    var confirmTip: Payload?
}

extension AudienceSession {
    /// Starts a tip of `amountCents` to a publication, all of it the publisher's. A tip of at least
    /// ``Publication/adFreeTipCents`` reads it without ads for ``Publication/adFreeDays``. Offer it only where
    /// ``AdFreeTips/isOffered(_:storefrontCountryCode:)`` says so. Asking again for the same amount soon after picks
    /// the same tip up.
    public func startAdFreeTip(publicationID: String, amountCents: Int, note: String? = nil,
                               showFirstName: Bool = false) async throws -> AdFreeTipCheckout
    {
        let variables: [String: GraphQLValue] = [
            "publicationId": .string(publicationID), "amountCents": .int(amountCents),
            "note": note.map { .string($0) } ?? .null, "showFirstName": .bool(showFirstName),
        ]
        let response = try await graphQL(Queries.startAdFreeTip, variables: variables,
                                         operationName: "StartAdFreeTip", as: StartAdFreeTipResponse.self)
        guard let payload = response.startTip, let id = payload.tip?.id,
              let string = payload.checkoutUrl, let url = URL(string: string)
        else { throw AdFreeTipUnavailable() }
        return AdFreeTipCheckout(tipID: id, checkoutURL: url)
    }

    /// Checks a tip with the payments provider, for when the reader comes back from the web checkout before the
    /// webhook arrives. Nil when there's no such tip of theirs.
    @discardableResult
    public func confirmTip(id: String) async throws -> TipConfirmation? {
        try await graphQL(Queries.confirmTip, variables: ["tipId": .string(id)], operationName: "ConfirmTip",
                          as: ConfirmTipResponse.self).confirmTip?.tip
    }
}
