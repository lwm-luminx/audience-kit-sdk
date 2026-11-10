package com.audiencekit.android

import android.content.Context
import com.audiencekit.DeviceAttestation
import com.audiencekit.DeviceAttestor
import com.google.android.gms.tasks.Task
import com.google.android.play.core.integrity.IntegrityManagerFactory
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
}

private suspend fun <T> Task<T>.await(): T = suspendCancellableCoroutine { continuation ->
    addOnSuccessListener { continuation.resume(it) }
    addOnFailureListener { continuation.resumeWithException(it) }
    addOnCanceledListener { continuation.cancel() }
}
