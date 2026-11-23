package com.audiencekit

import kotlinx.serialization.Serializable

// Privacy choices, per audience: what a member chooses about their data in this app's audience. Opting out of selling
// or sharing their personal information (CCPA/CPRA; a Global Privacy Control signal counts too) and of being counted
// in sponsors' viewer numbers are free, always offered and one switch each, the same either way. Where the audience
// sells one, a privacy pass turns off paid cards and every optional use of their data for a while: it's paid on the
// web, in the browser, so the apps offer it in US storefronts only, as with tips to read without ads. The API enforces
// every choice; the app only shows the switches. See the API's doc/PRIVACY_CHOICES.md. The same as the Swift SDK's
// PrivacyChoices.swift.

/** A privacy choice the audience's apps show. Unknown keys from a newer API are left out. */
public enum class PrivacyChoiceKey { SALE_SHARE_OPT_OUT, AD_MEASUREMENT, PERSONALIZED_ADS, PRIVACY_PASS }

/** What the audience offers: the choices to show, in order, and its privacy pass. */
public data class PrivacyOffer(
    /** The switches to show, opting out of selling or sharing first. */
    val choices: List<PrivacyChoiceKey>,
    /** What a pass costs, in US cents; null when none is for sale. */
    val passCents: Int? = null,
    /** How many days one pass lasts. */
    val passDays: Int = 30,
) {
    public companion object {
        /** When the API can't say: the opt-out of selling or sharing, which every audience offers. */
        public val MINIMUM: PrivacyOffer =
            PrivacyOffer(listOf(PrivacyChoiceKey.SALE_SHARE_OPT_OUT, PrivacyChoiceKey.AD_MEASUREMENT))
    }
}

/** How a member opted out of selling or sharing. */
public enum class PrivacyOptOutSource { CHOICE, GLOBAL_PRIVACY_CONTROL }

/** What the member chose in this audience, and what's in force once a privacy pass is counted. */
@Serializable
public data class PrivacyChoices(
    val saleShareOptedOut: Boolean = false,
    /** ISO 8601. */
    val saleShareOptedOutAt: String? = null,
    val saleShareOptOutSource: PrivacyOptOutSource? = null,
    /** Their choice to be counted in sponsors' weekly viewer numbers. On unless turned off. */
    val adMeasurement: Boolean = true,
    /** Whether they're counted now ([adMeasurement] and no privacy pass). */
    val countedInAdMeasurement: Boolean = true,
    /** Their agreement to ads based on their activity. Off unless turned on. */
    val personalizedAds: Boolean = false,
    /** Whether anything about them may be sold or shared for advertising. Nothing is today. */
    val mayShare: Boolean = true,
    /** ISO 8601: when their privacy pass ends; null when none is running. */
    val privacyPassUntil: String? = null,
) {
    val hasPrivacyPass: Boolean get() = privacyPassUntil != null

    /** Whether the switch for [key] is on. A privacy pass has no switch. */
    public fun isOn(key: PrivacyChoiceKey): Boolean = when (key) {
        PrivacyChoiceKey.SALE_SHARE_OPT_OUT -> saleShareOptedOut
        PrivacyChoiceKey.AD_MEASUREMENT -> adMeasurement
        PrivacyChoiceKey.PERSONALIZED_ADS -> personalizedAds
        PrivacyChoiceKey.PRIVACY_PASS -> hasPrivacyPass
    }

    public companion object {
        /** Before a member signs in, or when the API can't say: the defaults. */
        public val DEFAULTS: PrivacyChoices = PrivacyChoices()
    }
}

/** A started privacy pass: open [checkoutUrl] in the browser (not a WebView), then read [privacy] again on return. */
public data class PrivacyPassCheckout(val passId: String, val checkoutUrl: String)

/** The API's answer to [startPrivacyPass] had no checkout. */
public class PrivacyPassUnavailableException : Exception("A privacy pass isn't for sale here.")

/**
 * The words every app shows for its privacy choices, so they say the same thing. Not yet reviewed by a lawyer: see the
 * API's doc/PRIVACY_CHOICES.md.
 */
public object PrivacyChoicesCopy {
    /** The settings row and screen title: CCPA's alternative opt-out link name. */
    public const val TITLE: String = "Your privacy choices"

    public fun intro(appName: String): String =
        "These choices are for $appName only. Turning something off is as easy as turning it on, and none of the " +
            "free choices ever costs anything."

    public fun label(key: PrivacyChoiceKey): String = when (key) {
        PrivacyChoiceKey.SALE_SHARE_OPT_OUT -> "Do not sell or share my personal information"
        PrivacyChoiceKey.AD_MEASUREMENT -> "Count me in sponsors' viewer numbers"
        PrivacyChoiceKey.PERSONALIZED_ADS -> "Ads based on my activity"
        PrivacyChoiceKey.PRIVACY_PASS -> "Privacy pass"
    }

    public fun detail(key: PrivacyChoiceKey, appName: String): String = when (key) {
        PrivacyChoiceKey.SALE_SHARE_OPT_OUT ->
            "$appName doesn't sell your personal information or share it for advertising. Turn this on and it never " +
                "will, whatever changes."
        PrivacyChoiceKey.AD_MEASUREMENT ->
            "Sponsors only ever see how many different people saw their card each week, never who. Turn this off " +
                "and you aren't counted."
        PrivacyChoiceKey.PERSONALIZED_ADS ->
            "Off unless you turn it on. While it's off, ads are chosen only by the screen, the place and the night, " +
                "never by anything about you."
        PrivacyChoiceKey.PRIVACY_PASS ->
            "No Promoted or Sponsored cards, and none of your data used for ads, for a while."
    }

    /** Under the opt-out, when a Global Privacy Control signal turned it on. */
    public const val FROM_GLOBAL_PRIVACY_CONTROL: String = "Turned on by your browser's Global Privacy Control signal."

    /**
     * Whether to offer the pass in the storefront with [storefrontCountryCode] (Play's billing config country): it's
     * paid on the web, which the stores allow from US storefronts only.
     */
    public fun isPassOffered(offer: PrivacyOffer, storefrontCountryCode: String?, isWeb: Boolean = false): Boolean {
        if (PrivacyChoiceKey.PRIVACY_PASS !in offer.choices || offer.passCents == null) return false
        if (isWeb) return true
        return storefrontCountryCode?.uppercase() in AdFreeTips.WEB_CHECKOUT_STOREFRONTS
    }

    /** The button: "Go without ads for 30 days, $2.99". */
    public fun passButton(cents: Int, days: Int): String = "Go without ads for $days days, ${AdFreeTips.money(cents)}"

    public fun passExplanation(days: Int): String =
        "For $days days you'll see no Promoted or Sponsored cards, and none of your data is used for ads or counted " +
            "for sponsors. You pay once, on the web; nothing renews. The free choices above stay free either way."

    /** [until] is already formatted. */
    public fun passRunning(until: String): String =
        "Your privacy pass runs until $until. Thanks for supporting this community."

    public const val PENDING: String = "We're confirming your payment. Your pass starts as soon as it clears."
}

/** What the audience offers and what the member chose. Signed out, the choices are the defaults. */
public suspend fun AudienceKitClient.privacy(): Pair<PrivacyOffer, PrivacyChoices> {
    val response = graphQL(PrivacyQueries.READ, PrivacyResponse.serializer(), null, "Privacy")
    val offer = response.privacyOffer?.let { offer ->
        PrivacyOffer(
            offer.choices.mapNotNull { key -> PrivacyChoiceKey.entries.firstOrNull { it.name == key } },
            offer.passCents,
            offer.passDays,
        )
    } ?: PrivacyOffer.MINIMUM
    return offer to (response.me?.privacy ?: PrivacyChoices.DEFAULTS)
}

/** Changes the member's choices; each left null stays as it is. Returns them as they now stand. */
public suspend fun AudienceKitClient.updatePrivacyChoices(
    saleShareOptOut: Boolean? = null,
    adMeasurement: Boolean? = null,
    personalizedAds: Boolean? = null,
): PrivacyChoices = graphQL(
    PrivacyQueries.UPDATE,
    UpdatePrivacyChoicesResponse.serializer(),
    graphQLVariables(
        "saleShareOptOut" to saleShareOptOut, "adMeasurement" to adMeasurement, "personalizedAds" to personalizedAds,
    ),
    "UpdatePrivacyChoices",
).updatePrivacyChoices?.privacy ?: PrivacyChoices.DEFAULTS

/** Turns one switch on or off. */
public suspend fun AudienceKitClient.setPrivacyChoice(key: PrivacyChoiceKey, on: Boolean): PrivacyChoices = when (key) {
    PrivacyChoiceKey.SALE_SHARE_OPT_OUT -> updatePrivacyChoices(saleShareOptOut = on)
    PrivacyChoiceKey.AD_MEASUREMENT -> updatePrivacyChoices(adMeasurement = on)
    PrivacyChoiceKey.PERSONALIZED_ADS -> updatePrivacyChoices(personalizedAds = on)
    PrivacyChoiceKey.PRIVACY_PASS -> privacy().second
}

/**
 * Starts paying for a privacy pass. [returnUrl] is the app's own link (or a web address) Checkout comes back to. Offer
 * it only where [PrivacyChoicesCopy.isPassOffered] says so.
 */
public suspend fun AudienceKitClient.startPrivacyPass(returnUrl: String? = null): PrivacyPassCheckout {
    val payload = graphQL(
        PrivacyQueries.START_PASS,
        StartPrivacyPassResponse.serializer(),
        graphQLVariables("returnUrl" to returnUrl),
        "StartPrivacyPass",
    ).startPrivacyPass
    val id = payload?.passId
    val url = payload?.checkoutUrl
    if (id == null || url == null) throw PrivacyPassUnavailableException()
    return PrivacyPassCheckout(id, url)
}

internal object PrivacyQueries {
    const val READ: String = """
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

    const val UPDATE: String = """
        mutation UpdatePrivacyChoices(${'$'}saleShareOptOut: Boolean, ${'$'}adMeasurement: Boolean, ${'$'}personalizedAds: Boolean) {
          updatePrivacyChoices(input: { saleShareOptOut: ${'$'}saleShareOptOut, adMeasurement: ${'$'}adMeasurement, personalizedAds: ${'$'}personalizedAds }) {
            privacy {
              saleShareOptedOut saleShareOptedOutAt saleShareOptOutSource adMeasurement countedInAdMeasurement
              personalizedAds mayShare privacyPassUntil
            }
          }
        }
    """

    const val START_PASS: String = """
        mutation StartPrivacyPass(${'$'}returnUrl: String) {
          startPrivacyPass(input: { returnUrl: ${'$'}returnUrl }) { checkoutUrl passId }
        }
    """
}

@Serializable
internal data class PrivacyResponse(val privacyOffer: Offer? = null, val me: Me? = null) {
    @Serializable
    data class Offer(val choices: List<String> = emptyList(), val passCents: Int? = null, val passDays: Int = 30)

    @Serializable
    data class Me(val privacy: PrivacyChoices? = null)
}

@Serializable
internal data class UpdatePrivacyChoicesResponse(val updatePrivacyChoices: Payload? = null) {
    @Serializable
    data class Payload(val privacy: PrivacyChoices? = null)
}

@Serializable
internal data class StartPrivacyPassResponse(val startPrivacyPass: Payload? = null) {
    @Serializable
    data class Payload(val checkoutUrl: String? = null, val passId: String? = null)
}
