package com.audiencekit

import kotlinx.serialization.KSerializer
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.descriptors.PrimitiveKind
import kotlinx.serialization.descriptors.PrimitiveSerialDescriptor
import kotlinx.serialization.descriptors.SerialDescriptor
import kotlinx.serialization.encoding.Decoder
import kotlinx.serialization.encoding.Encoder
import kotlinx.serialization.json.JsonElement

/** The audience a client is scoped to. */
@Serializable
public data class Audience(
    val id: String,
    val name: String,
    val subdomain: String,
    val theme: AudienceTheme? = null,
)

/** An audience's look, as GraphQL returns it: a preset, a tagline and color token overrides. */
@Serializable
public data class AudienceTheme(
    val preset: String,
    val tagline: String? = null,
    val light: List<ThemeToken> = emptyList(),
    val dark: List<ThemeToken> = emptyList(),
)

/** One design-system color token, e.g. `accent` = `#b8236f`. */
@Serializable
public data class ThemeToken(val name: String, val value: String)

/** The Facebook page behind a venue or person: its name and pictures. */
@Serializable
public data class Page(
    val id: String,
    val name: String,
    /** Profile picture, as the API sends it. Use [AudienceKitClient.url] to resolve relative paths. */
    val photoUrl: String? = null,
    val bannerUrl: String? = null,
)

/** A city or region the audience is active in. */
@Serializable
public data class AudienceLocale(
    val id: String,
    val name: String? = null,
    val label: String? = null,
    val cityNames: List<String>? = null,
    val bannerUrl: String? = null,
    /** Its listing profile: `profile { places { placeId } }`. */
    val profile: ListingProfile = ListingProfile(),
) {
    /** Its Google place ID (a city or region), when an admin has set one. */
    val googlePlaceId: String? get() = profile.places?.placeId
}

/**
 * A venue's, person's or locale's public profile: GraphQL's `profile` mixin (`IListingProfile`), with the facebook
 * and places modules' parts. Only what the SDK's queries select; a part the query left out is null.
 */
@Serializable
public data class ListingProfile(
    /** The facebook module's part: `profile { facebook { page } }`. */
    val facebook: FacebookProfile? = null,
    /** The places module's part: `profile { places { placeId } }`. */
    val places: PlacesProfile? = null,
)

/** A listing's Facebook side: GraphQL's `IFacebookProfile`. */
@Serializable
public data class FacebookProfile(
    /** Its Facebook Page, when it has one. */
    val page: Page? = null,
)

/** A listing's or location's Google Maps side: GraphQL's `IPlacesProfile`. */
@Serializable
public data class PlacesProfile(
    /** Its Google place ID, when it has one. */
    val placeId: String? = null,
)

/** A place: a Google place with a point. */
@Serializable
public data class Location(
    val id: String,
    /** The point as the API serializes it (WKT, e.g. `POINT (-122.42 37.77)`). */
    val point: String? = null,
    /** Its full address, when known. */
    val address: String? = null,
    /** The places module's part: `places { placeId }`. */
    val places: PlacesProfile? = null,
) {
    /** Its Google place ID, when an admin or the researcher has set one. */
    val googlePlaceId: String? get() = places?.placeId

    /** [point] parsed into latitude and longitude, when it is a WKT point. */
    val coordinate: Coordinate? get() = point?.let(Coordinate::fromWkt)
}

/** A venue in the audience. */
@Serializable
public data class Venue(
    val id: String,
    val hidden: Boolean,
    val order: Int,
    val photoUrl: String? = null,
    val bannerUrl: String? = null,
    /** Its listing profile: `profile { facebook { page } }`. */
    val profile: ListingProfile = ListingProfile(),
    val locale: AudienceLocale,
    val location: Location? = null,
    @SerialName("name") private val venueName: String? = null,
    /** The audience's tags on it, by name. */
    val tags: List<Tag> = emptyList(),
) {
    /** Its Facebook Page; venues added without one have none. */
    val page: Page? get() = profile.facebook?.page

    /** The venue's own name, falling back to its Facebook Page's. */
    val name: String get() = venueName ?: page?.name.orEmpty()
}

/** A person (performer, promoter, DJ...) the audience follows. */
@Serializable
public data class Person(
    val id: String,
    val order: Int,
    val global: Boolean,
    val likeRequired: Boolean,
    /** Their listing profile: `profile { facebook { page } }`. */
    val profile: ListingProfile = ListingProfile(),
    @SerialName("name") private val personName: String? = null,
    /** The audience's tags on them, by name. */
    val tags: List<Tag> = emptyList(),
) {
    /** Their Facebook Page; talent added by name has none yet. */
    val page: Page? get() = profile.facebook?.page

    /** Their name as the audience shows it, falling back to their Facebook Page's. */
    val name: String get() = personName ?: page?.name.orEmpty()
}

/** One of the audience's own labels, like "Drag" or "Resident DJ", on its people, events and venues. */
@Serializable
public data class Tag(
    val id: String,
    val name: String,
    /** A `#rrggbb` color for its chip, or null for the theme's accent. */
    val color: String? = null,
    /** Whether people can identify with it (see [TribeIdentification]). */
    val tribe: Boolean = false,
)

/**
 * Someone identifying with one of the audience's tribes. A private one may be sensitive (HIV status, say): the API
 * only ever shows it to them and to people in the same tribe, and apps should keep it discreet.
 */
@Serializable
public data class TribeIdentification(val tag: Tag, val isPrivate: Boolean)

/** The tribes people can identify with in an audience, and which of them the signed-in user has. */
public data class Tribes(val available: List<Tag>, val mine: List<TribeIdentification>)

/** The signed-in user's own profile (`me { self }`, a SelfUser): what only they see as well as their public fields. */
@Serializable
public data class SelfUser(
    val id: String,
    val name: String? = null,
    val firstName: String? = null,
    val lastName: String? = null,
    val emailAddress: String? = null,
    val isAdmin: Boolean? = null,
    /** Whether they can be reached now; null when the query didn't ask. */
    val presence: Presence? = null,
)

/** One of the signed-in user's friends. */
@Serializable
public data class Friend(
    val id: String,
    val name: String? = null,
    val facebookId: String? = null,
    /** Whether they can be reached now; null when the query didn't ask. */
    val presence: Presence? = null,
)

/**
 * Whether someone can be reached right now: GraphQL's `Presence` on users, friends and chat messages.
 * The API shows the real value only to the person, their friends and admins; everyone else gets [OFFLINE].
 *
 * Decoding is case-insensitive, so it also reads the chat room's `presence` frames
 * (`{"type":"presence","user_id":"…","presence":"online"}`), and an unknown value decodes as [OFFLINE].
 */
@Serializable(with = PresenceSerializer::class)
public enum class Presence {
    /** Connected to a chat room now. */
    ONLINE,

    /** Not in chat, but signed in on a device that gets push notifications. */
    PUSH,

    /** Neither, or not for this viewer to see. */
    OFFLINE,
}

internal object PresenceSerializer : KSerializer<Presence> {
    override val descriptor: SerialDescriptor =
        PrimitiveSerialDescriptor("com.audiencekit.Presence", PrimitiveKind.STRING)

    override fun deserialize(decoder: Decoder): Presence {
        val raw = decoder.decodeString()
        return Presence.entries.firstOrNull { it.name.equals(raw, ignoreCase = true) } ?: Presence.OFFLINE
    }

    override fun serialize(encoder: Encoder, value: Presence) {
        encoder.encodeString(value.name)
    }
}

/** Any record, as `node(id:)` returns it: its UUID and its GraphQL type. */
@Serializable
public data class Node(
    val id: String,
    /** The GraphQL type name, e.g. `Venue`. */
    @SerialName("__typename") val typename: String? = null,
)

/** Whether the signed-in user is going to an event. The names are the GraphQL enum's values. */
@Serializable
public enum class RSVPState { ATTENDING, MAYBE, DECLINED, UNSURE }

/** Why someone counts as going to an event: they RSVPed, or they hold a ticket (a ticket is an RSVP). */
@Serializable
public enum class RSVPSource { RSVP, TICKET }

/**
 * Who's going to an event, from its rsvp module (`event { rsvp { … } }`): everyone who RSVPed attending and, where the
 * audience sells tickets, everyone holding one.
 *
 * [mine] is the signed-in user's answer ([RSVPState.ATTENDING] when they hold a ticket, [RSVPState.UNSURE] signed
 * out) and [mineSource] why they count as going, when they do. [counts] is there only for the event's staff (its
 * audience's admins and its listing's managers). [attendees] is empty signed out; signed in, the viewer's friends
 * come in full and everyone else as first name and last initial ("Aurora B."), unless the viewer is staff.
 */
public data class EventRSVP(
    val count: Int,
    val mine: RSVPState,
    val mineSource: RSVPSource? = null,
    val counts: RSVPCounts? = null,
    val attendees: List<EventAttendee> = emptyList(),
)

/** How many are going (RSVPed attending or holding a ticket), interested, and holding tickets. Staff only. */
@Serializable
public data class RSVPCounts(val going: Int, val interested: Int, val tickets: Int = 0)

/**
 * Who someone is, as the signed-in user may see them (`Profile`): the user's [id], their [name] (in full for
 * themself, their friends and staff; "Aurora B." for anyone else) and their picture.
 */
@Serializable
public data class Profile(
    val id: String,
    val name: String,
    val avatarUrl: String? = null,
)

/** Someone going to an event: who they are, and how they count as going. */
@Serializable
public data class EventAttendee(
    val profile: Profile,
    val friend: Boolean = false,
    val source: RSVPSource = RSVPSource.RSVP,
)

/**
 * An amount of money as the API gives it: whole [cents] of a [currency] (its lower-case ISO 4217 code, e.g. `usd`).
 * $10.00 is `Money(1000, "usd")`.
 */
@Serializable
public data class Money(
    /** The amount in the currency's minor unit (cents for dollars). */
    val cents: Int,
    /** The currency's ISO 4217 code in lower case. */
    val currency: String = "usd",
) {
    public companion object {
        /** Money in US dollars. */
        public fun usd(cents: Int): Money = Money(cents, "usd")
    }
}

/**
 * What it costs to get into a venue on a night. Show [total], the all-in price; when [payable] is
 * true it can be paid in the app with [AudienceKitClient.buyCover], otherwise it's paid at the door.
 */
@Serializable
public data class CoverCharge(
    /** The cover the venue receives. */
    val amount: Money,
    /** What the buyer pays, all in. */
    val total: Money,
    /** The Hot Mess fee in it. */
    val fee: Money = Money(0, amount.currency),
    /** The night it is for, as an ISO 8601 date (`2026-10-09`). A night runs 6am to 6am. */
    val night: String,
    /** When the cover starts, a TimeOfDay (`HH:MM`, local), e.g. `21:00`. */
    val from: String? = null,
    /** Whether it can be paid in the app. */
    val payable: Boolean = false,
    /** The event that night, when it sets the night's cover. */
    val event: CoverEvent? = null,
)

/** The event an [Admission] or [CoverCharge] is for. */
@Serializable
public data class CoverEvent(val id: String, val name: String? = null)

/** The venue an [Admission] is for. */
@Serializable
public data class CoverVenue(val id: String, val name: String? = null, val photoUrl: String? = null)

/**
 * Where a cover payment stands. The names are the GraphQL enum's values; values from a newer API decode
 * as [UNKNOWN].
 */
@Serializable
public enum class AdmissionStatus {
    /** Paying in the app has started but not finished. */
    PENDING,

    /** Paid: the pass works. */
    PAID,

    /** The payment was declined. */
    FAILED,

    /** The payment was abandoned. */
    CANCELED,

    /** The money went back; the pass no longer works. */
    REFUNDED,

    /** The buyer disputed the charge with their bank. */
    DISPUTED,

    UNKNOWN,
}

/**
 * Someone's cover for one night at a venue, and their pass. Make the pass's QR code with
 * [CoverPass.code] from [passSecret], which only the buyer gets.
 */
@Serializable
public data class Admission(
    val id: String,
    val status: AdmissionStatus = AdmissionStatus.UNKNOWN,
    /** The night it is for, as an ISO 8601 date. */
    val night: String,
    /** The cover. */
    val amount: Money = Money(0),
    /** The Hot Mess fee. */
    val fee: Money = Money(0),
    /** What the buyer paid. */
    val total: Money = Money(0),
    /** Whether the buyer can refund it themselves: paid, not scanned in, and the night isn't over. */
    val isRefundable: Boolean = false,
    /** How many times the door has scanned it. */
    val scanCount: Int = 0,
    /** When the door first scanned it, as ISO 8601. */
    val checkedInAt: String? = null,
    val createdAt: String? = null,
    /** The Base64 key the pass's QR code is made with. The buyer only; null for everyone else. */
    val passSecret: String? = null,
    /** The buyer: their name for the pass and the door, their picture so the door can match faces. */
    val profile: Profile? = null,
    val venue: CoverVenue? = null,
    /** The event that night, if it set the cover. */
    val event: CoverEvent? = null,
) {
    val isPaid: Boolean get() = status == AdmissionStatus.PAID

    /** The pass's QR code at [epochSeconds], or `null` without a [passSecret]. */
    public fun passCode(epochSeconds: Long = System.currentTimeMillis() / 1000): String? =
        passSecret?.let { CoverPass.code(id, it, epochSeconds) }
}

/** What [AudienceKitClient.buyCover] returns: the pass, and what Stripe's payment sheet needs. */
@Serializable
public data class CoverPurchase(
    /** The pass, pending until the payment succeeds. */
    val admission: Admission,
    /** `STRIPE` or `SQUARE`: Stripe venues pay with Stripe's payment sheet, Square venues with Square's In-App Payments SDK. */
    val provider: String = "STRIPE",
    /** Stripe: for the payment sheet; `null` once it's paid. */
    val paymentIntentClientSecret: String? = null,
    /** Stripe: the audience's publishable key. */
    val publishableKey: String? = null,
    /** Stripe: the venue's account; the payment is a direct charge on it. */
    val stripeAccountId: String? = null,
    /** Square: the audience's application ID, for `InAppPaymentsSdk.squareApplicationId`. */
    val squareApplicationId: String? = null,
    /** Square: the venue's location that gets paid. */
    val squareLocationId: String? = null,
) {
    val isSquare: Boolean get() = provider == "SQUARE"

    /** Whether there's nothing left to pay. */
    val isPaid: Boolean get() = admission.isPaid || (!isSquare && paymentIntentClientSecret == null)
}

/** A venue's cover tonight and the signed-in user's pass for it. */
@Serializable
public data class VenueCover(
    val id: String,
    val name: String? = null,
    /** Its tickets mixin, carrying the cover mixin inside it: `tickets { cover { charge viewerAdmission } }`. */
    val tickets: ViewerTickets? = null,
) {
    /** Its cover mixin: tonight's charge and the signed-in user's pass. */
    val cover: ViewerCover? get() = tickets?.cover

    /** Tonight's cover, or `null` when there is none. */
    val coverCharge: CoverCharge? get() = cover?.charge

    /** The signed-in user's cover for tonight, paid or being paid. */
    val viewerAdmission: Admission? get() = cover?.viewerAdmission
}

/** The part of a venue's `tickets` mixin a fan reads: the cover inside it. */
@Serializable
public data class ViewerTickets(val cover: ViewerCover? = null)

/** The part of a venue's `tickets { cover }` mixin a fan reads. */
@Serializable
public data class ViewerCover(
    /** Tonight's cover, or `null` when there is none. */
    val charge: CoverCharge? = null,
    /** The signed-in user's cover for tonight, paid or being paid. */
    val viewerAdmission: Admission? = null,
)
