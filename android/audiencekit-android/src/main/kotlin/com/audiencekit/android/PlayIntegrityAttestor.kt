package com.audiencekit.android

import android.content.Context
import com.audiencekit.DeviceAttestation
import com.audiencekit.DeviceAttestor
import com.google.android.gms.tasks.Task
import com.google.android.play.core.integrity.IntegrityManagerFactory
import com.google.android.play.core.integrity.IntegrityServiceException
import com.google.android.play.core.integrity.IntegrityTokenRequest
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException

/**
 * Google Play Integrity for sign-ins (SafetyNet Attestation's successor). Each sign-in requests a classic integrity
 * token whose nonce is the API's one-use challenge; the API has Google decode it and checks the app is the audience's,
 * signed with its key and recognized by Play, on a device that meets device integrity.
 *
 * [AudienceKitClient] made with a [Context] uses one by default. Emulators, devices without Play services and
 * sideloaded builds sign in without proof (or with a failing verdict), which only an audience that enforces
 * attestation refuses. [cloudProjectNumber] is needed only for apps distributed outside Google Play.
 */
public class PlayIntegrityAttestor(
    context: Context,
    private val cloudProjectNumber: Long? = null,
) : DeviceAttestor {
    private val appContext = context.applicationContext
    private val manager by lazy { IntegrityManagerFactory.create(appContext) }

    override suspend fun attest(challenge: String): DeviceAttestation {
        val request = IntegrityTokenRequest.builder()
            .setNonce(challenge)
            .apply { cloudProjectNumber?.let { setCloudProjectNumber(it) } }
            .build()
        val response = manager.requestIntegrityToken(request).await()
        return DeviceAttestation(
            platform = "android",
            challenge = challenge,
            packageName = appContext.packageName,
            token = response.token(),
        )
    }

    /**
     * Play Integrity's own error, as `pi_<code>`, so the API can tell the person what to do (update Play services, sign
     * in to the Play Store, use a phone with Google Play) and admins can see it in New Relic.
     */
    override fun failureReason(error: Throwable): String {
        val code = (error as? IntegrityServiceException)?.errorCode ?: return "attest_failed"
        return "pi_" + (PLAY_INTEGRITY_ERRORS[code] ?: "error_${-code}")
    }

    private companion object {
        /**
         * Play Integrity's classic error codes (`IntegrityErrorCode`), by value: the constants live in a Java
         * annotation, so they're spelled out here. An unknown one is sent as `error_<n>`.
         */
        val PLAY_INTEGRITY_ERRORS = mapOf(
            -1 to "api_not_available",
            -2 to "play_store_not_found",
            -3 to "network_error",
            -4 to "play_store_account_not_found",
            -5 to "app_not_installed",
            -6 to "play_services_not_found",
            -7 to "app_uid_mismatch",
            -8 to "too_many_requests",
            -9 to "cannot_bind_to_service",
            -10 to "nonce_too_short",
            -11 to "nonce_too_long",
            -12 to "google_server_unavailable",
            -13 to "nonce_is_not_base64",
            -14 to "play_store_version_outdated",
            -15 to "play_services_version_outdated",
            -16 to "cloud_project_number_is_invalid",
            -18 to "client_transient_error",
            -100 to "internal_error",
        )
    }
}

private suspend fun <T> Task<T>.await(): T = suspendCancellableCoroutine { continuation ->
    addOnSuccessListener { continuation.resume(it) }
    addOnFailureListener { continuation.resumeWithException(it) }
    addOnCanceledListener { continuation.cancel() }
}
