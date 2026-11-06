package com.audiencekit

import kotlinx.serialization.Serializable

/**
 * The GraphQL documents behind the client's typed helpers. Public so apps can reuse the fragments
 * in their own operations and decode into the same models.
 */
public object Queries {
    public const val PAGE_FIELDS: String = "id name photoUrl bannerUrl"
    public const val LOCALE_FIELDS: String = "id name label cityNames bannerUrl profile { places { placeId } }"
    public const val TAG_FIELDS: String = "id name color"

    // Fragments with module fields take the audience's [SchemaShape]: the API leaves a module's fields out of an
    // audience that hasn't installed it, and asking for one fails the whole operation.

    /** The types whose fields the listing documents depend on. */
    public val LISTING_TYPES: List<String> = listOf("Locale", "ListingProfile", "Venue", "Location", "Person", "Event")

    /** A locale, with its Google place ID (Listings and Google Places). */
    public fun localeFields(shape: SchemaShape): String =
        "id name label cityNames bannerUrl" +
            if (shape.has("Locale", "profile") && shape.has("ListingProfile", "places")) " profile { places { placeId } }" else ""

    /** A venue in a list: its Facebook Page (Listings and Facebook) and its location's Google place ID. */
    public fun venueFields(shape: SchemaShape): String {
        val page = if (shape.has("Venue", "profile") && shape.has("ListingProfile", "facebook")) {
            "profile { facebook { page { $PAGE_FIELDS } } }"
        } else {
            ""
        }
        val place = if (shape.has("Location", "places")) " places { placeId }" else ""
        return "id name hidden order photoUrl bannerUrl $page locale { ${localeFields(shape)} } " +
            "location { id point address$place } tags { $TAG_FIELDS }"
    }
    public const val MONEY_FIELDS: String = "cents currency"
    public const val PROFILE_FIELDS: String = "id name avatarUrl"
    public const val COVER_CHARGE_FIELDS: String =
        "amount { $MONEY_FIELDS } total { $MONEY_FIELDS } fee { $MONEY_FIELDS } night from payable event { id name } " +
            "coatCheck { amount { $MONEY_FIELDS } fee { $MONEY_FIELDS } total { $MONEY_FIELDS } night payable }"

    /** An [Admission], with the pass secret the buyer makes the QR code from. */
    public const val ADMISSION_FIELDS: String =
        "id status kind night quantity tier claimCheckNumber amount { $MONEY_FIELDS } fee { $MONEY_FIELDS } " +
            "total { $MONEY_FIELDS } isRefundable " +
            "passSecret scanCount checkedInAt createdAt profile { $PROFILE_FIELDS } venue { id name photoUrl } event { id name }"

    public val audience: String = """
        query Audience {
          id name subdomain theme { preset tagline light { name value } dark { name value } }
        }
    """.trimIndent()

    public val venues: String get() = venues(SchemaShape.EVERYTHING)

    /** [venues] with only the module fields [shape] has. */
    public fun venues(shape: SchemaShape): String = """
        query Venues {
          venues { list { nodes { ${venueFields(shape)} } } }
        }
    """.trimIndent()

    public val people: String get() = people(SchemaShape.EVERYTHING)

    public fun people(shape: SchemaShape): String {
        val page = if (shape.has("Person", "profile") && shape.has("ListingProfile", "facebook")) {
            "profile { facebook { page { $PAGE_FIELDS } } }"
        } else {
            ""
        }
        return """
            query People {
              people {
                list { nodes { id name order global likeRequired $page tags { $TAG_FIELDS } } }
              }
            }
        """.trimIndent()
    }

    public val locales: String get() = locales(SchemaShape.EVERYTHING)

    public fun locales(shape: SchemaShape): String = """
        query Locales {
          locales { ${localeFields(shape)} }
        }
    """.trimIndent()

    public val me: String = """
        query Me {
          me { self { id name firstName lastName emailAddress isAdmin presence } }
        }
    """.trimIndent()

    public val closestLocale: String get() = closestLocale(SchemaShape.EVERYTHING)

    public fun closestLocale(shape: SchemaShape): String = """
        query ClosestLocale(${'$'}near: CoordinatesInput!) {
          closestLocale(near: ${'$'}near) { ${localeFields(shape)} }
        }
    """.trimIndent()

    /**
     * Records the user's position and says where that is: `venue` when they're in one, else `locale` and its
     * `nearbyVenues`, plus `audience` for its mixins. Select the fields the app needs (with the mixins it reads, such
     * as `venue { friends { list { name } } }`) and decode the result yourself; `$position` is a
     * [Coordinates.toGraphQLValue].
     */
    public fun reportLocation(fields: String): String = """
        mutation ReportLocation(${'$'}position: CoordinatesInput!) {
          reportLocation(input: { position: ${'$'}position }) { $fields }
        }
    """.trimIndent()

    /** An event's rsvp mixin for the signed-in user: how many are going, and their own answer. */
    public const val RSVP_FIELDS: String = "count mine mineSource"
    public const val EVENT_ATTENDEE_FIELDS: String = "profile { $PROFILE_FIELDS } friend source"

    public val rsvpEvent: String = """
        mutation RSVPEvent(${'$'}eventId: ID!, ${'$'}state: RSVPState!) {
          rsvpEvent(input: { eventId: ${'$'}eventId, state: ${'$'}state }) { event { id rsvp { $RSVP_FIELDS } } }
        }
    """.trimIndent()

    public val cancelRsvp: String = """
        mutation CancelRSVP(${'$'}eventId: ID!) {
          cancelRsvp(input: { eventId: ${'$'}eventId }) { event { id rsvp { $RSVP_FIELDS } } }
        }
    """.trimIndent()

    /** Who's going to an event: [RSVP_FIELDS], the staff-only counts and the first `$first` attendees. */
    public val eventRsvp: String = """
        query EventRSVP(${'$'}id: ID!, ${'$'}first: Int) {
          events {
            event(id: ${'$'}id) {
              id
              rsvp {
                $RSVP_FIELDS counts { going interested tickets }
                attendees(first: ${'$'}first) { nodes { $EVENT_ATTENDEE_FIELDS } }
              }
            }
          }
        }
    """.trimIndent()

    /** The tribes people can identify with here, and the signed-in user's own. */
    public val tribes: String = """
        query Tribes {
          id tribes: tags(tribes: true) { $TAG_FIELDS tribe }
          me { self { id tribes { isPrivate tag { $TAG_FIELDS tribe } } } }
        }
    """.trimIndent()

    public val identifyWithTribe: String = """
        mutation IdentifyWithTribe(${'$'}tagId: ID!, ${'$'}isPrivate: Boolean) {
          identifyWithTribe(input: { tagId: ${'$'}tagId, isPrivate: ${'$'}isPrivate }) {
            tribes { isPrivate tag { $TAG_FIELDS tribe } }
          }
        }
    """.trimIndent()

    public val leaveTribe: String = """
        mutation LeaveTribe(${'$'}tagId: ID!) {
          leaveTribe(input: { tagId: ${'$'}tagId }) { tribes { isPrivate tag { $TAG_FIELDS tribe } } }
        }
    """.trimIndent()

    public val registerDevice: String = """
        mutation RegisterDevice(${'$'}notificationToken: String!) {
          registerDevice(input: { notificationToken: ${'$'}notificationToken }) { registered }
        }
    """.trimIndent()

    /** The signed-in user's cover passes, newest first. */
    public val admissions: String = """
        query Admissions {
          me { cover { admissions { nodes { $ADMISSION_FIELDS } } } }
        }
    """.trimIndent()

    /** A venue's cover tonight and the signed-in user's pass for it. */
    public val venueCover: String get() = venueCover(SchemaShape.EVERYTHING)

    /** [venueCover], asking only for the venue where the audience doesn't have the Ticketing and Cover modules. */
    public fun venueCover(shape: SchemaShape): String {
        val cover = if (shape.has("Venue", "tickets") && shape.has("VenueTickets", "cover")) {
            " tickets { cover { charge { $COVER_CHARGE_FIELDS } viewerAdmission { $ADMISSION_FIELDS } " +
                "viewerCoatCheck { $ADMISSION_FIELDS } } }"
        } else {
            ""
        }
        return """
            query VenueCover(${'$'}id: ID!) {
              venues { venue(id: ${'$'}id) { id name$cover } }
            }
        """.trimIndent()
    }

    public val buyCover: String = """
        mutation BuyCover(${'$'}venueId: ID!) {
          buyCover(input: { venueId: ${'$'}venueId }) {
            admission { $ADMISSION_FIELDS }
            provider paymentIntentClientSecret publishableKey stripeAccountId squareApplicationId squareLocationId
          }
        }
    """.trimIndent()

    public val buyCoatCheck: String = """
        mutation BuyCoatCheck(${'$'}venueId: ID!, ${'$'}quantity: Int) {
          buyCoatCheck(input: { venueId: ${'$'}venueId, quantity: ${'$'}quantity }) {
            admission { $ADMISSION_FIELDS }
            provider paymentIntentClientSecret publishableKey stripeAccountId squareApplicationId squareLocationId
          }
        }
    """.trimIndent()

    public val payCover: String = """
        mutation PayCover(${'$'}admissionId: ID!, ${'$'}sourceId: String!, ${'$'}verificationToken: String) {
          payCover(input: { admissionId: ${'$'}admissionId, sourceId: ${'$'}sourceId, verificationToken: ${'$'}verificationToken }) {
            admission { $ADMISSION_FIELDS }
          }
        }
    """.trimIndent()

    public val confirmCover: String = """
        mutation ConfirmCover(${'$'}admissionId: ID!) {
          confirmCover(input: { admissionId: ${'$'}admissionId }) { admission { $ADMISSION_FIELDS } }
        }
    """.trimIndent()

    public val refundAdmission: String = """
        mutation RefundAdmission(${'$'}admissionId: ID!) {
          refundAdmission(input: { admissionId: ${'$'}admissionId }) { admission { $ADMISSION_FIELDS } }
        }
    """.trimIndent()

    public val node: String = """
        query Node(${'$'}id: ID!) {
          node(id: ${'$'}id) { __typename id }
        }
    """.trimIndent()
}

/** A connection read as `nodes { … }`: the mixin lists (`venues { list }`, `me { cover { admissions } }`) are connections. */
@Serializable internal data class Nodes<T>(val nodes: List<T>)

@Serializable
internal data class VenuesResponse(val venues: Venues? = null) {
    @Serializable internal data class Venues(val list: Nodes<Venue>)
}

@Serializable
internal data class PeopleResponse(val people: People? = null) {
    @Serializable internal data class People(val list: Nodes<Person>)
}

@Serializable internal data class LocalesResponse(val locales: List<AudienceLocale> = emptyList())
/** `me` is the viewer's state (UserState); `self` their own profile (SelfUser). */
@Serializable
internal data class MeResponse(val me: Me? = null) {
    @Serializable internal data class Me(val self: SelfUser)
}
@Serializable internal data class NodeResponse(val node: Node? = null)
@Serializable internal data class ClosestLocaleResponse(val closestLocale: AudienceLocale? = null)

@Serializable
internal data class RegisterDeviceResponse(val registerDevice: Payload) {
    @Serializable internal data class Payload(val registered: Boolean)
}

@Serializable
internal data class TribesResponse(val tribes: List<Tag> = emptyList(), val me: Me? = null) {
    @Serializable internal data class Me(val self: Self)
    @Serializable internal data class Self(val tribes: List<TribeIdentification>)
}

@Serializable internal data class TribesPayload(val tribes: List<TribeIdentification>)
@Serializable internal data class IdentifyWithTribeResponse(val identifyWithTribe: TribesPayload)
@Serializable internal data class LeaveTribeResponse(val leaveTribe: TribesPayload)

/** An event's rsvp mixin as the API sends it, attendees in a connection. */
@Serializable
internal data class RSVPPayloadEvent(val rsvp: Rsvp) {
    @Serializable
    internal data class Rsvp(
        val count: Int,
        val mine: RSVPState,
        val mineSource: RSVPSource? = null,
        val counts: RSVPCounts? = null,
        val attendees: Nodes<EventAttendee>? = null,
    ) {
        fun toEventRSVP(): EventRSVP = EventRSVP(count, mine, mineSource, counts, attendees?.nodes.orEmpty())
    }
}

@Serializable internal data class RSVPMutationPayload(val event: RSVPPayloadEvent)
@Serializable internal data class RSVPEventResponse(val rsvpEvent: RSVPMutationPayload)
@Serializable internal data class CancelRSVPResponse(val cancelRsvp: RSVPMutationPayload)

@Serializable
internal data class EventRSVPResponse(val events: Events) {
    @Serializable internal data class Events(val event: RSVPPayloadEvent? = null)
}

@Serializable
internal data class AdmissionsResponse(val me: Me? = null) {
    @Serializable internal data class Me(val cover: Cover)
    @Serializable internal data class Cover(val admissions: Nodes<Admission>)
}

@Serializable internal data class BuyCoverResponse(val buyCover: CoverPurchase)
@Serializable internal data class BuyCoatCheckResponse(val buyCoatCheck: CoverPurchase)

@Serializable
internal data class VenueCoverResponse(val venues: Venues) {
    @Serializable internal data class Venues(val venue: VenueCover? = null)
}

@Serializable internal data class AdmissionPayload(val admission: Admission)
@Serializable internal data class ConfirmCoverResponse(val confirmCover: AdmissionPayload)

@Serializable internal data class PayCoverResponse(val payCover: AdmissionPayload)
@Serializable internal data class RefundAdmissionResponse(val refundAdmission: AdmissionPayload)

