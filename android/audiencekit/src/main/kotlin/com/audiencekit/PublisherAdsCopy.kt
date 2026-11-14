package com.audiencekit

/**
 * The words for the one-time note a reader acknowledges before their first Soapbox story: a publisher's ads are the
 * publisher's own relationship, kept so it can keep paying writers; the app takes no cut, and its own sponsored spots
 * are separate. The same words as `PublisherAdsCopy` on iOS. Keep who acknowledged it with
 * `com.audiencekit.android.PublisherAdsAcknowledgement`.
 */
public object PublisherAdsCopy {
    public const val TITLE: String = "Publishers run their own ads"

    /** The note, naming the app ("Hot Mess"). */
    public fun body(appName: String): String =
        "Stories here come from independent publishers. Each publisher chooses the ads in its stories and answers for " +
            "them: that ad relationship is the publisher's own, and it's there so they can keep paying writers and " +
            "making the work you read.\n\n" +
            "$appName takes no cut, just as it takes none from performers' tips. $appName's own sponsored spots are " +
            "separate and always marked Sponsored, and $appName never shares your data with a publisher's advertisers."

    public const val ACCEPT: String = "I understand"
    public const val DECLINE: String = "Not now"

    /** A user ID as the acknowledgement keeps it, or null for nobody signed in. */
    public fun normalizedUserId(userId: String?): String? = userId?.trim()?.lowercase()?.takeIf { it.isNotEmpty() }
}
