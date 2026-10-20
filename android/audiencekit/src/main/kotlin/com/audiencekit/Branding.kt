package com.audiencekit

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

/**
 * What `GET /v1/branding?host=…` returns: who the audience is, its look, and the Facebook app its
 * sign-in uses. Public, so an app can skin itself before anyone signs in.
 */
@Serializable
public data class Branding(
    val audience: AudienceSummary,
    @SerialName("facebook_app_id") val facebookAppId: String? = null,
    /**
     * The Facebook Login for Business configuration to open the login dialog with, as `config_id`.
     * A Business-type Facebook app refuses a login that asks for permissions without one.
     */
    @SerialName("facebook_login_config_id") val facebookLoginConfigId: String? = null,
    val theme: Theme = Theme(),
) {
    @Serializable
    public data class AudienceSummary(val id: String, val name: String, val subdomain: String)

    /** An audience's theme as branding sends it: token overrides keyed by token name. */
    @Serializable
    public data class Theme(
        /** Design system preset, e.g. `default` or `hot_mess`. */
        val preset: String = "default",
        val tagline: String? = null,
        /** Light-mode overrides, e.g. `mapOf("accent" to "#9c1c62")`. */
        val light: Map<String, String> = emptyMap(),
        /** Dark-mode overrides. */
        val dark: Map<String, String> = emptyMap(),
    ) {
        /** The value of a token, preferring the dark override in dark mode. */
        public fun color(token: String, dark: Boolean = false): RGBAColor? {
            val hex = if (dark) this.dark[token] ?: light[token] else light[token]
            return hex?.let(RGBAColor::fromHex)
        }
    }
}

/**
 * A color parsed from a `#rgb`, `#rrggbb` or `#rrggbbaa` hex string, with components from 0 to 1.
 * On Android, [toArgb] gives the `@ColorInt` that views and Compose's `Color(Int)` take.
 */
public data class RGBAColor(
    val red: Double,
    val green: Double,
    val blue: Double,
    val alpha: Double = 1.0,
) {
    /** The color as a packed `0xAARRGGBB` int. */
    public fun toArgb(): Int {
        fun channel(value: Double) = (value.coerceIn(0.0, 1.0) * 255 + 0.5).toInt()
        return (channel(alpha) shl 24) or (channel(red) shl 16) or (channel(green) shl 8) or channel(blue)
    }

    public companion object {
        /** A colour packed as `0xRRGGBBAA`, as DesignTokens writes them. */
        public fun fromRgba(rgba: Long): RGBAColor = RGBAColor(
            red = ((rgba shr 24) and 0xFF) / 255.0,
            green = ((rgba shr 16) and 0xFF) / 255.0,
            blue = ((rgba shr 8) and 0xFF) / 255.0,
            alpha = (rgba and 0xFF) / 255.0,
        )

        public fun fromHex(hex: String): RGBAColor? {
            var digits = hex.trim().removePrefix("#")
            if (digits.length == 3) digits = digits.map { "$it$it" }.joinToString("")
            if (digits.length != 6 && digits.length != 8) return null
            val value = digits.toULongOrNull(16)?.toLong() ?: return null

            val rgba = if (digits.length == 6) (value shl 8) or 0xFF else value
            return RGBAColor(
                red = ((rgba shr 24) and 0xFF) / 255.0,
                green = ((rgba shr 16) and 0xFF) / 255.0,
                blue = ((rgba shr 8) and 0xFF) / 255.0,
                alpha = (rgba and 0xFF) / 255.0,
            )
        }
    }
}
