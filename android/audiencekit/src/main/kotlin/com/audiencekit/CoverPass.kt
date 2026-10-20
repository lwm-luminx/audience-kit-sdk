package com.audiencekit

import java.util.Base64
import javax.crypto.Mac
import javax.crypto.spec.SecretKeySpec

/**
 * The QR code on a cover pass. The app makes it from the pass's [Admission.passSecret] every
 * [WINDOW_SECONDS], so it works with no signal and a screenshot stops scanning within a minute:
 *
 * ```
 * HMC1.<admission id>.<window>.<signature>
 * ```
 *
 * where window is the Unix time divided by [WINDOW_SECONDS] and signature is the first 16 characters of
 * the unpadded URL-safe Base64 HMAC-SHA256 of `<admission id>.<window>`, keyed with the Base64-decoded
 * secret. The door accepts a couple of windows either side, for clock drift between the phones.
 */
public object CoverPass {
    public const val PREFIX: String = "HMC1"
    public const val WINDOW_SECONDS: Long = 30

    /** The window [epochSeconds] falls in. */
    public fun window(epochSeconds: Long): Long = Math.floorDiv(epochSeconds, WINDOW_SECONDS)

    /** Seconds from [epochSeconds] until the code changes. */
    public fun secondsUntilNextWindow(epochSeconds: Long): Long = WINDOW_SECONDS - Math.floorMod(epochSeconds, WINDOW_SECONDS)

    /** The pass's code at [epochSeconds]. Throws [IllegalArgumentException] when [passSecret] isn't Base64. */
    public fun code(admissionId: String, passSecret: String, epochSeconds: Long): String {
        val window = window(epochSeconds)
        return listOf(PREFIX, admissionId, window.toString(), signature(admissionId, passSecret, window)).joinToString(".")
    }

    /** Whether [code] looks like a Hot Mess pass, before asking the API. */
    public fun isPassCode(code: String): Boolean {
        val parts = code.trim().split(".")
        return parts.size == 4 && parts[0] == PREFIX && parts[1].isNotEmpty() &&
            parts[2].isNotEmpty() && parts[2].all(Char::isDigit) && parts[3].isNotEmpty()
    }

    internal fun signature(admissionId: String, passSecret: String, window: Long): String {
        val key = Base64.getDecoder().decode(passSecret)
        val mac = Mac.getInstance("HmacSHA256")
        mac.init(SecretKeySpec(key, "HmacSHA256"))
        val digest = mac.doFinal("$admissionId.$window".toByteArray(Charsets.UTF_8))
        return Base64.getUrlEncoder().withoutPadding().encodeToString(digest).take(16)
    }
}
