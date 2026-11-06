import AudienceCore
import Foundation

/// The GraphQL documents behind the client's typed helpers: this SDK version's fragments, which the models in
/// `Models.swift` decode. Internal: apps run their own operations through `AudienceSession.graphQL` and decode into
/// their own models.
enum Queries {
    static let pageFields = "id name photoUrl bannerUrl"
    /// A tag on a venue, person or event: its name and chip color.
    static let tagFields = "id name color"

    // Fragments with module fields take the audience's ``SchemaShape``: the API leaves a module's fields out of an
    // audience that hasn't installed it, and asking for one fails the whole operation.

    /// A locale, with its Google place ID (Listings and Google Places).
    static func localeFields(_ shape: SchemaShape) -> String {
        "id name label cityNames bannerUrl" + (shape.has("Locale", "profile") && shape.has("ListingProfile", "places")
            ? " profile { places { placeId } }" : "")
    }

    /// A venue in a list: its Facebook Page (Listings and Facebook) and its location's Google place ID.
    static func venueFields(_ shape: SchemaShape) -> String {
        let page = shape.has("Venue", "profile") && shape.has("ListingProfile", "facebook")
            ? "profile { facebook { page { \(pageFields) } } }" : ""
        let place = shape.has("Location", "places") ? " places { placeId }" : ""
        return """
        id name hidden order photoUrl bannerUrl \(page)
        locale { \(localeFields(shape)) }
        location { id point address\(place) }
        tags { \(tagFields) }
        """
    }

    /// A person's home venue or gig venue: where it is, and which of the signed-in user's friends are there now
    /// (Friends).
    static func personVenueFields(_ shape: SchemaShape) -> String {
        "id name photoUrl locale { id name }" + (shape.has("Venue", "friends")
            ? " friends { list { nodes { id name facebookId presence } } }" : "")
    }

    /// One of a person's events (`PersonEvent`), on its own or as the node of a `PersonEventInvolvement`. Its
    /// `venue` is the events mixin: a display name ("To be announced" when there is none) and the venue, if any.
    static func personEventFields(_ shape: SchemaShape) -> String {
        "id name startAt locale { id name }"
            + (shape.has("Event", "venue") ? " venue { name venue { \(personVenueFields(shape)) } }" : "")
            + " tags { \(tagFields) }"
    }

    /// The types whose fields the documents above depend on.
    static let listingTypes = ["Locale", "ListingProfile", "Venue", "Location", "Person", "Event"]

    static let audience = """
    query Audience {
      id name subdomain theme { preset tagline light { name value } dark { name value } }
    }
    """

    static func venues(_ shape: SchemaShape) -> String {
        """
        query Venues {
          venues { list { nodes { \(venueFields(shape)) } } }
        }
        """
    }

    static func people(_ shape: SchemaShape) -> String {
        let page = shape.has("Person", "profile") && shape.has("ListingProfile", "facebook")
            ? "profile { facebook { page { \(pageFields) } } }" : ""
        let venues = shape.has("Person", "venues") ? "venues { home { \(personVenueFields(shape)) } }" : ""
        let events = shape.has("Person", "events")
            ? "events { involvements { edges { relationship role via { id name } node { \(personEventFields(shape)) } } } }"
            : ""
        return """
        query People {
          people {
            list {
              nodes {
                id name avatarUrl bannerUrl order global likeRequired \(page)
                \(venues)
                locales { id name }
                \(events)
                tags { \(tagFields) }
              }
            }
          }
        }
        """
    }

    static func locales(_ shape: SchemaShape) -> String {
        """
        query Locales {
          locales { \(localeFields(shape)) }
        }
        """
    }

    static let me = """
    query Me {
      me { self { id name firstName lastName emailAddress isAdmin presence } }
    }
    """

    static func closestLocale(_ shape: SchemaShape) -> String {
        """
        query ClosestLocale($near: CoordinatesInput!) {
          closestLocale(near: $near) { \(localeFields(shape)) }
        }
        """
    }

    static let rsvpEvent = """
    mutation RSVPEvent($eventId: ID!, $state: RSVPState!) {
      rsvpEvent(input: { eventId: $eventId, state: $state }) { event { id rsvp { mine } } }
    }
    """

    /// The tribes people can identify with here, and the signed-in user's own.
    static let tribes = """
    query Tribes {
      id tribes: tags(tribes: true) { \(tagFields) tribe }
      me { self { id tribes { isPrivate tag { \(tagFields) tribe } } } }
    }
    """

    static let identifyWithTribe = """
    mutation IdentifyWithTribe($tagId: ID!, $isPrivate: Boolean) {
      identifyWithTribe(input: { tagId: $tagId, isPrivate: $isPrivate }) {
        tribes { isPrivate tag { \(tagFields) tribe } }
      }
    }
    """

    static let leaveTribe = """
    mutation LeaveTribe($tagId: ID!) {
      leaveTribe(input: { tagId: $tagId }) { tribes { isPrivate tag { \(tagFields) tribe } } }
    }
    """

    static let registerDevice = """
    mutation RegisterDevice($notificationToken: String!, $appId: String, $sandbox: Boolean) {
      registerDevice(input: { notificationToken: $notificationToken, appId: $appId, sandbox: $sandbox }) { registered }
    }
    """

    /// A ``Money``.
    static let moneyFields = "cents currency"
    /// A ``CoverCharge``.
    static let coverChargeFields = """
    amount { \(moneyFields) } fee { \(moneyFields) } total { \(moneyFields) } night from payable event { id name }
    """
    /// An ``Admission``: the pass secret the buyer makes the QR code from, and the buyer's ``Profile`` for the door.
    static let admissionFields = """
    id status night amount { \(moneyFields) } total { \(moneyFields) } isRefundable passSecret scanCount checkedInAt \
    profile { id name avatarUrl } venue { id name photoUrl } event { id name }
    """

    /// The types ``venueCover(_:)`` and ``venueOffers(_:)`` depend on.
    static let venueTicketTypes = ["Venue", "VenueTickets"]

    /// A venue's cover tonight, or just the venue where the audience doesn't have the Ticketing and Cover modules.
    static func venueCover(_ shape: SchemaShape) -> String {
        let cover = shape.has("Venue", "tickets") && shape.has("VenueTickets", "cover") ? """
         tickets { cover { charge { \(coverChargeFields) } viewerAdmission { \(admissionFields) } } }
        """ : ""
        return """
        query VenueCover($id: ID!) {
          venues { venue(id: $id) { id name\(cover) } }
        }
        """
    }

    /// Every way into a venue on a night, or just the venue where the audience doesn't have the Ticketing module.
    static func venueOffers(_ shape: SchemaShape) -> String {
        // A variable the document doesn't use is an error, so $night goes with the field.
        let hasTickets = shape.has("Venue", "tickets")
        let offers = hasTickets ? " tickets { offers(night: $night) { nodes { \(admissionOfferFields) } } }" : ""
        return """
        query VenueOffers($id: ID!\(hasTickets ? ", $night: ISO8601Date" : "")) {
          venues { venue(id: $id) { id\(offers) } }
        }
        """
    }

    static let admissions = """
    query Admissions {
      me { cover { admissions { nodes { \(admissionFields) } } } }
    }
    """

    static let buyCover = """
    mutation BuyCover($venueId: ID!) {
      buyCover(input: { venueId: $venueId }) {
        admission { \(admissionFields) }
        provider paymentIntentClientSecret publishableKey stripeAccountId squareApplicationId squareLocationId
      }
    }
    """

    static let payCover = """
    mutation PayCover($admissionId: ID!, $sourceId: String!, $verificationToken: String) {
      payCover(input: { admissionId: $admissionId, sourceId: $sourceId, verificationToken: $verificationToken }) {
        admission { \(admissionFields) }
      }
    }
    """

    static let confirmCover = """
    mutation ConfirmCover($admissionId: ID!) {
      confirmCover(input: { admissionId: $admissionId }) { admission { \(admissionFields) } }
    }
    """

    static let refundAdmission = """
    mutation RefundAdmission($admissionId: ID!) {
      refundAdmission(input: { admissionId: $admissionId }) { admission { \(admissionFields) } }
    }
    """

    static let node = """
    query Node($id: ID!) {
      node(id: $id) { __typename id }
    }
    """
}

/// A connection read as `nodes { … }`: the mixin lists (`venues { list }`, `me { cover { admissions } }`) are connections.
struct Nodes<Element: Decodable & Sendable>: Decodable, Sendable { var nodes: [Element] }

/// `venues { list { nodes } }` on the root, the audience.
struct VenuesResponse: Decodable, Sendable {
    struct Mixin: Decodable, Sendable { var list: Nodes<Venue> }

    private var venues: Mixin?
    var list: [Venue] { venues?.list.nodes ?? [] }
}

/// `people { list { nodes } }` on the root, the audience.
struct PeopleResponse: Decodable, Sendable {
    struct Mixin: Decodable, Sendable { var list: Nodes<Person> }

    private var people: Mixin?
    var list: [Person] { people?.list.nodes ?? [] }
}

/// `locales` on the root, the audience.
struct LocalesResponse: Decodable, Sendable { var locales: [AudienceLocale]? }
/// `me { self }`: the viewer's state (UserState), and their own profile in it (SelfUser).
struct MeResponse: Decodable, Sendable {
    struct State: Decodable, Sendable {
        var profile: SelfUser?

        private enum CodingKeys: String, CodingKey { case profile = "self" }
    }

    var me: State?
}
struct NodeResponse: Decodable, Sendable { var node: Node? }
struct ClosestLocaleResponse: Decodable, Sendable { var closestLocale: AudienceLocale? }
struct RegisterDeviceResponse: Decodable, Sendable {
    struct Payload: Decodable, Sendable { var registered: Bool }
    var registerDevice: Payload
}
struct TribesResponse: Decodable, Sendable {
    struct Profile: Decodable, Sendable { var tribes: [TribeIdentification] }
    struct Mine: Decodable, Sendable {
        var profile: Profile?

        private enum CodingKeys: String, CodingKey { case profile = "self" }
    }
    var tribes: [Tag]?
    var me: Mine?
}
struct TribesPayload: Decodable, Sendable { var tribes: [TribeIdentification] }
struct IdentifyWithTribeResponse: Decodable, Sendable { var identifyWithTribe: TribesPayload }
struct LeaveTribeResponse: Decodable, Sendable { var leaveTribe: TribesPayload }
/// `rsvpEvent { event { rsvp { mine } } }`: the signed-in user's answer, from the event's rsvp mixin.
struct RSVPEventResponse: Decodable, Sendable {
    struct RSVP: Decodable, Sendable { var mine: RSVPState }
    struct Event: Decodable, Sendable { var rsvp: RSVP }
    struct Payload: Decodable, Sendable { var event: Event }
    var rsvpEvent: Payload
}
/// `venues { venue(id:) }`.
/// `venues { venue { tickets { offers { nodes } } } }`.
struct VenueOffersResponse: Decodable, Sendable {
    struct Offers: Decodable, Sendable { var offers: Nodes<AdmissionOffer>? }
    struct Venue: Decodable, Sendable { var tickets: Offers? }
    struct Venues: Decodable, Sendable { var venue: Venue? }

    var venues: Venues
}

struct VenueCoverResponse: Decodable, Sendable {
    struct Venues: Decodable, Sendable { var venue: VenueCover? }

    var venues: Venues
    var venue: VenueCover? { venues.venue }
}

/// `me { cover { admissions { nodes } } }`: the viewer's passes are theirs, under `me`.
struct AdmissionsResponse: Decodable, Sendable {
    struct Cover: Decodable, Sendable { var admissions: Nodes<Admission> }
    struct Me: Decodable, Sendable { var cover: Cover }

    var me: Me?
    var admissions: [Admission] { me?.cover.admissions.nodes ?? [] }
}

struct BuyCoverResponse: Decodable, Sendable { var buyCover: CoverPurchase }
struct AdmissionPayload: Decodable, Sendable { var admission: Admission }
struct ConfirmCoverResponse: Decodable, Sendable { var confirmCover: AdmissionPayload }
struct PayCoverResponse: Decodable, Sendable { var payCover: AdmissionPayload }
struct RefundAdmissionResponse: Decodable, Sendable { var refundAdmission: AdmissionPayload }
