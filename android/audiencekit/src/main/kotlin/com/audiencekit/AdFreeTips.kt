package com.audiencekit

import kotlinx.serialization.Serializable

// Tip to read without ads: a reader tips a Soapbox publication, all of the tip goes to the publisher (the app takes
// nothing, as with performers' tips), and a big enough tip reads that publication without ads for a while. Because
// the ads going away ties the tip to content in the app, the stores don't count it as a gift, so it can't use the
// in-app payment sheet: the reader pays on the web, in their browser, and the apps offer it in US storefronts only.
// See the API's doc/SOAPBOX.md, "Tip to read without ads". The same as the Swift SDK's AdFreeTips.swift.

/**
 * A started tip to a publication: open [checkoutUrl] in the reader's browser (not a WebView), then call [confirmTip]
 * when they come back to the app.
 */
public data class AdFreeTipCheckout(
    val tipId: String,
    /** The web checkout, on the publisher's own Stripe account. Good for two hours. */
    val checkoutUrl: String,
)

/** Where a tip stands. */
public enum class TipConfirmationStatus { PENDING, PAID, FAILED, CANCELED, REFUNDED, DISPUTED }

/** Where a tip stands after [confirmTip]. */
@Serializable
public data class TipConfirmation(
    val id: String,
    val status: TipConfirmationStatus,
    /** ISO 8601: when the time reading its publication without ads that it gave ends; null when it gave none. */
    val readsAdFreeUntil: String? = null,
) {
    val isPaid: Boolean get() = status == TipConfirmationStatus.PAID
}

/** The API's answer to [startAdFreeTip] had no web checkout: the publication can't take tips here yet. */
public class AdFreeTipUnavailableException : Exception("This publication can't take tips here yet.")

/** When the apps may offer tip to read without ads, and the words for it. */
public object AdFreeTips {
    /**
     * Storefronts where the apps may link out to a web checkout: the United States only, for now. Play's billing
     * config gives alpha-2 codes ("US"), StoreKit alpha-3 ("USA"); both are accepted.
     */
    public val WEB_CHECKOUT_STOREFRONTS: Set<String> = setOf("US", "USA")

    /** Whether to offer it in the storefront with [storefrontCountryCode]. False when the storefront is unknown. */
    public fun isOffered(adFreeOffered: Boolean?, storefrontCountryCode: String?): Boolean =
        adFreeOffered == true && storefrontCountryCode?.uppercase() in WEB_CHECKOUT_STOREFRONTS

    public fun isOffered(publication: Publication, storefrontCountryCode: String?): Boolean =
        isOffered(publication.adFreeOffered, storefrontCountryCode)

    public fun isOffered(publication: PublicationSummary, storefrontCountryCode: String?): Boolean =
        isOffered(publication.adFreeOffered, storefrontCountryCode)

    /** The button: "Tip QSaltLake to read without ads". */
    public fun button(publicationName: String): String = "Tip $publicationName to read without ads"

    /** Under the button, before the reader leaves for the checkout. */
    public fun explanation(publicationName: String, tipCents: Int, days: Int): String =
        "A tip of ${money(tipCents)} or more goes straight to $publicationName, all of it: we take no cut. In " +
            "return you'll read $publicationName here without ads for $days days. You'll pay on the web, in your " +
            "browser."

    public const val CONTINUE_TO_CHECKOUT: String = "Continue to checkout"
    public const val PENDING: String = "We're confirming your tip. Ads go away as soon as it clears."
    public const val NOT_PAID: String = "Your tip wasn't paid, so nothing changed."

    /** Shown where the ads would be, once a reader reads the publication without ads; [until] is already formatted. */
    public fun thanks(publicationName: String, until: String?): String =
        if (until == null) "Thanks for supporting $publicationName. No ads here for you."
        else "Thanks for supporting $publicationName. No ads here for you until $until."

    internal fun money(cents: Int): String =
        if (cents % 100 == 0) "$" + (cents / 100) else "$" + "%d.%02d".format(cents / 100, cents % 100)
}

/**
 * Starts a tip of [amountCents] to a publication, all of it the publisher's. A tip of at least
 * [Publication.adFreeTipCents] reads it without ads for [Publication.adFreeDays]. Offer it only where
 * [AdFreeTips.isOffered] says so. Asking again for the same amount soon after picks the same tip up.
 */
public suspend fun AudienceKitClient.startAdFreeTip(
    publicationId: String,
    amountCents: Int,
    note: String? = null,
    showFirstName: Boolean = false,
): AdFreeTipCheckout {
    val payload = graphQL(
        AdFreeTipQueries.START,
        StartAdFreeTipResponse.serializer(),
        graphQLVariables(
            "publicationId" to publicationId, "amountCents" to amountCents, "note" to note,
            "showFirstName" to showFirstName,
        ),
        "StartAdFreeTip",
    ).startTip
    val id = payload?.tip?.id
    val url = payload?.checkoutUrl
    if (id == null || url == null) throw AdFreeTipUnavailableException()
    return AdFreeTipCheckout(id, url)
}

/**
 * Checks a tip with the payments provider, for when the reader comes back from the web checkout before the webhook
 * arrives. Null when there's no such tip of theirs.
 */
public suspend fun AudienceKitClient.confirmTip(id: String): TipConfirmation? = graphQL(
    AdFreeTipQueries.CONFIRM,
    ConfirmTipResponse.serializer(),
    graphQLVariables("tipId" to id),
    "ConfirmTip",
).confirmTip?.tip

internal object AdFreeTipQueries {
    const val START: String = """
        mutation StartAdFreeTip(${'$'}publicationId: ID!, ${'$'}amountCents: Int!, ${'$'}note: String, ${'$'}showFirstName: Boolean) {
          startTip(input: { publicationId: ${'$'}publicationId, amountCents: ${'$'}amountCents, note: ${'$'}note, showFirstName: ${'$'}showFirstName }) {
            checkoutUrl
            tip { id }
          }
        }
    """

    const val CONFIRM: String = """
        mutation ConfirmTip(${'$'}tipId: ID!) {
          confirmTip(input: { tipId: ${'$'}tipId }) { tip { id status readsAdFreeUntil } }
        }
    """
}

@Serializable
internal data class StartAdFreeTipResponse(val startTip: Payload? = null) {
    @Serializable
    data class Payload(val checkoutUrl: String? = null, val tip: Tip? = null)

    @Serializable
    data class Tip(val id: String)
}

@Serializable
internal data class ConfirmTipResponse(val confirmTip: Payload? = null) {
    @Serializable
    data class Payload(val tip: TipConfirmation? = null)
}
