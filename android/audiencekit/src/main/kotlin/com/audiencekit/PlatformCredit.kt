package com.audiencekit

import java.net.URLEncoder
import java.util.Calendar

/**
 * The platform and company credit every AudienceKit app shows at the foot of its About or Settings screen: "Powered by
 * AudienceKit", "A Love Wins Media product", AudienceKit's policy links and an invitation to bring AudienceKit to your
 * own venue. Love Wins Media is drawn in the pink-to-amber gradient of audiencekit.com's band. The same words, links
 * and colours as iOS's `PlatformCredit`.
 *
 * Every link carries `utm_source` (the app), `utm_medium=app` and `utm_campaign` (which part was tapped), so
 * audiencekit.com's analytics show which apps send people. Nothing about the person goes with it.
 */
public object PlatformCredit {
    public const val PLATFORM_NAME: String = "AudienceKit"
    public const val COMPANY_NAME: String = "Love Wins Media"
    public const val COMPANY_LEGAL_NAME: String = "Love Wins Media, Inc."
    public const val PLATFORM_SITE: String = "https://audiencekit.com/"
    public const val COMPANY_SITE: String = "https://lovewins.media/"

    public const val POWERED_BY_PREFIX: String = "Powered by "
    public const val PRODUCT_PREFIX: String = "A "
    public const val PRODUCT_SUFFIX: String = " product"
    public const val CALL_TO_ACTION: String = "Bring AudienceKit to your venue"

    public val poweredBy: String get() = POWERED_BY_PREFIX + PLATFORM_NAME
    public val product: String get() = PRODUCT_PREFIX + COMPANY_NAME + PRODUCT_SUFFIX

    /** The whole credit as one sentence, for TalkBack. */
    public val spoken: String get() = "$poweredBy. $product."

    /** "© 2026 Love Wins Media, Inc." */
    public fun copyright(year: Int = Calendar.getInstance().get(Calendar.YEAR)): String = "© $year $COMPANY_LEGAL_NAME"

    /** One of AudienceKit's policy pages on audiencekit.com. */
    public data class Policy(val title: String, val path: String)

    /** In the order the footer shows them. */
    public val policies: List<Policy> = listOf(
        Policy("Privacy", "privacy/"),
        Policy("Terms", "terms/"),
        Policy("Child safety", "child-safety/"),
        Policy("Contact", "contact/"),
    )

    /** The company name's gradient, start to end: darker on light backgrounds so it keeps contrast. */
    public val gradientLight: List<String> = listOf("#db2777", "#d97706")
    public val gradientDark: List<String> = listOf("#f472b6", "#fbbf24")

    /** A link to [path] on audiencekit.com, tagged with the app it came from ([source]) and what was tapped. */
    public fun platformUrl(path: String = "", campaign: String = "credit", source: String? = null): String =
        tagged(PLATFORM_SITE + path, campaign, source)

    public fun companyUrl(source: String? = null): String = tagged(COMPANY_SITE, "credit", source)

    public fun callToActionUrl(source: String? = null): String = platformUrl(campaign = "venue_cta", source = source)

    public fun policyUrl(policy: Policy, source: String? = null): String =
        platformUrl(policy.path, campaign = "policy", source = source)

    private fun tagged(url: String, campaign: String, source: String?): String {
        val from = source?.takeIf { it.isNotEmpty() } ?: "audiencekit-app"
        return "$url?utm_source=${encode(from)}&utm_medium=app&utm_campaign=${encode(campaign)}"
    }

    private fun encode(value: String) = URLEncoder.encode(value, "UTF-8")
}
