package com.audiencekit

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

/**
 * Proof that a sign-in comes from the audience's genuine app on a genuine device, sent with every sign-in as
 * `attestation` (the API's doc/DEVICE_ATTESTATION.md). On Android it's Play Integrity (`PlayIntegrityAttestor` in
 * `audiencekit-android`); the Swift SDK sends App Attest. Each audience decides whether the API only records it or
 * refuses sign-ins without it.
 */
@Serializable
public data class DeviceAttestation(
    /** `android` or `ios`. */
    val platform: String,
    /** The one-use challenge from `POST /v1/token/attestation` this proof covers. */
    val challenge: String? = null,
    /** Play Integrity: the app's package name. */
    @SerialName("package_name") val packageName: String? = null,
    /** Play Integrity: the integrity token, requested with [challenge] as its nonce. */
    val token: String? = null,
    /** App Attest (iOS): the key's identifier, attestation object and assertion, Base64. */
    @SerialName("key_id") val keyId: String? = null,
    val attestation: String? = null,
    val assertion: String? = null,
    /** The device can't attest (an emulator, no Play services, the service failing); [reason] says why. */
    val unsupported: Boolean? = null,
    val reason: String? = null,
) {
    public companion object {
        /** A device that can't attest, and why (a short word: `emulator`, `unsupported`, `attest_failed`…). */
        public fun unsupported(platform: String, reason: String): DeviceAttestation =
            DeviceAttestation(platform = platform, unsupported = true, reason = reason)
    }
}

/**
 * Signs a sign-in challenge on this device. [AudienceKitClient] asks the API for a challenge, hands it here and sends
 * the result with the sign-in; when the API says it doesn't know the key, it calls [forgetKey] and tries once more.
 */
public interface DeviceAttestor {
    /** Why this device can't attest at all, or null when it can. When it can't, no challenge is fetched. */
    public suspend fun unsupportedReason(): String? = null

    /**
     * Proof over [challenge]. Throwing, or answering [DeviceAttestation.unsupported], signs in without proof, which an
     * audience that enforces attestation refuses.
     */
    public suspend fun attest(challenge: String): DeviceAttestation

    /** Forgets any key, so the next [attest] starts over. Play Integrity has none. */
    public suspend fun forgetKey() {}
}

/**
 * What a login screen shows when this device can't prove it is genuine (no Play Integrity on Android, no App Attest
 * on iOS), so nobody finds out only when a sign-in fails. [AudienceKitClient.deviceAttestationNotice] builds it from
 * what the device can do and what the audience requires.
 *
 * [reason] is a short word (`emulator`, `unsupported`, `no_attestor`). When [blocksSignIn] is true the audience
 * refuses sign-ins without attestation, so signing in on this device will fail: say so.
 */
public data class DeviceAttestationNotice(
    val reason: String,
    val blocksSignIn: Boolean,
    val title: String,
    val message: String,
) {
    public companion object {
        public fun of(reason: String, blocksSignIn: Boolean, message: String? = null): DeviceAttestationNotice =
            DeviceAttestationNotice(
                reason = reason,
                blocksSignIn = blocksSignIn,
                title = if (blocksSignIn) "Sign-in is blocked on this device" else "This device can't be verified",
                message = message ?: defaultMessage(blocksSignIn),
            )

        /** The same words the API sends, for when it couldn't be reached. */
        public fun defaultMessage(blocksSignIn: Boolean): String {
            val cause = "This device can't prove it's a genuine phone running the real app " +
                "(Apple's App Attest or Google's Play Integrity isn't available on it)"
            return if (blocksSignIn) "$cause, so sign-in is blocked here. Try another phone."
            else "$cause. You can still sign in for now."
        }
    }
}

/** `deviceAttestation` in `GET /v1/token/methods`. */
@Serializable
internal data class DeviceAttestationPolicyEnvelope(val deviceAttestation: DeviceAttestationPolicy? = null)

@Serializable
internal data class DeviceAttestationPolicy(val mode: String, val required: Boolean? = null, val warning: String? = null)

/** `POST /v1/token/attestation`'s answer. */
@Serializable
internal data class AttestationChallenge(val challenge: String, val mode: String? = null)
