package com.audiencekit

import java.net.URLEncoder

/**
 * The AudienceKit staff apps: Focus for an audience's curators, Velvet for venues, Backstage for performers and
 * promoters. Every AudienceKit app links to them (Hot Mess's "Open in Velvet", AudienceKit's own cards about getting
 * one, Focus's invite codes), so their names, links and URL schemes live here once, as on iOS.
 *
 * Whether one is installed: `StaffApps.installed(context)` in audiencekit-android (it needs each [androidPackage] in
 * the app manifest's `<queries>`).
 */
public enum class StaffApp(
    /** The key the API uses (`staffApp` on a promo card). */
    public val key: String,
    /** The name on the home screen. */
    public val appName: String,
    /** Who it's for, in a few words. */
    public val tagline: String,
) {
    FOCUS("focus", "Focus", "Curate and moderate your audience"),
    VELVET("velvet", "Velvet", "Run the night at your venue"),
    BACKSTAGE("backstage", "Backstage", "Your nights, profile and tips"),
    ;

    /** Whether it's still in beta, so links say "Join the beta". */
    public val isBeta: Boolean get() = this == VELVET

    /** Its Android package (the production build; Next builds add `.next`). */
    public val androidPackage: String get() = "com.audiencekit.$appName"

    /** Its URL scheme, `audiencekit-velvet` and so on. */
    public val urlScheme: String get() = "audiencekit-$key"

    /**
     * audiencekit.com's page for the app, which sends each phone to its store (or the beta): the link and QR code to
     * share. [source] (the app's package, say) goes along as `utm_source`.
     */
    public fun downloadUrl(source: String? = null, campaign: String = "staff_app"): String =
        PlatformCredit.platformUrl("apps/$key/", campaign, source)

    /** A button's words: "Open in Velvet", or "Get Backstage" / "Join the Velvet beta" when the phone doesn't have it. */
    public fun linkTitle(installed: Boolean): String = when {
        installed -> "Open in $appName"
        isBeta -> "Join the $appName beta"
        else -> "Get $appName"
    }

    internal fun link(host: String, id: String, audienceId: String?): String =
        "$urlScheme://$host?id=${encode(id)}" + (audienceId?.let { "&audience=${encode(it)}" } ?: "")

    public companion object {
        /** The app with the API's key, or null for one this SDK doesn't know. */
        public fun fromKey(key: String?): StaffApp? = entries.firstOrNull { it.key == key }

        /**
         * Opens Velvet on a venue's workspace: `audiencekit-velvet://venue?id=<venue>&audience=<audience>`, and with
         * [eventId] on that event's page there (`&event=<event>`).
         */
        @JvmOverloads
        public fun velvet(venueId: String, audienceId: String?, eventId: String? = null): String =
            VELVET.link("venue", venueId, audienceId) + (eventId?.let { "&event=${encode(it)}" } ?: "")

        /** Opens Backstage on a person's page: `audiencekit-backstage://person?id=<person>&audience=<audience>`. */
        public fun backstage(personId: String, audienceId: String?): String =
            BACKSTAGE.link("person", personId, audienceId)

        private fun encode(value: String) = URLEncoder.encode(value, "UTF-8")
    }
}
