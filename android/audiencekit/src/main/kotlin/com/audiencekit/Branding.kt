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

        /**
         * The color for text and icons on a [token] fill, such as `accent` or `spectrum-3`: the theme's
         * `on-<token>` when it reaches WCAG AA (4.5:1) on that fill, otherwise near-black or white, whichever reads
         * better. A light accent (Hack Different's lime) gets dark text even when the theme leaves `on-accent` out.
         * `null` when the theme has no [token]; fall back to the preset's own pair then.
         */
        public fun foreground(on: String, dark: Boolean = false): RGBAColor? {
            val fill = color(on, dark) ?: return null
            val given = color("on-$on", dark)
            if (given != null && given.contrastRatio(fill) >= RGBAColor.MINIMUM_TEXT_CONTRAST) return given
            return fill.readableForeground()
        }

        /** Text and icons on `accent` fills (primary buttons, own chat bubbles, selected chips). See [foreground]. */
        public fun onAccent(dark: Boolean = false): RGBAColor? = foreground("accent", dark)
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

    /** WCAG 2 relative luminance, from 0 (black) to 1 (white). Alpha is ignored. */
    public val relativeLuminance: Double
        get() {
            fun linear(channel: Double): Double {
                val c = channel.coerceIn(0.0, 1.0)
                return if (c <= 0.04045) c / 12.92 else Math.pow((c + 0.055) / 1.055, 2.4)
            }
            return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
        }

    /** WCAG 2 contrast ratio with [other], from 1 to 21. */
    public fun contrastRatio(other: RGBAColor): Double {
        val a = relativeLuminance
        val b = other.relativeLuminance
        return (maxOf(a, b) + 0.05) / (minOf(a, b) + 0.05)
    }

    /** [INK_ON_LIGHT] or [WHITE], whichever has more contrast on this color as a fill. */
    public fun readableForeground(): RGBAColor =
        if (contrastRatio(INK_ON_LIGHT) >= contrastRatio(WHITE)) INK_ON_LIGHT else WHITE

    public companion object {
        /** WCAG AA for body text: 4.5:1. */
        public const val MINIMUM_TEXT_CONTRAST: Double = 4.5

        /** The near-black the design system puts on light fills (`on-spectrum-N`), #111411. */
        public val INK_ON_LIGHT: RGBAColor = RGBAColor(0x11 / 255.0, 0x14 / 255.0, 0x11 / 255.0)
        public val WHITE: RGBAColor = RGBAColor(1.0, 1.0, 1.0)

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
