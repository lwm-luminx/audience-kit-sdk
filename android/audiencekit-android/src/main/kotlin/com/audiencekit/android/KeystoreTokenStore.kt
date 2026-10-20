package com.audiencekit.android

import android.content.Context
import android.content.SharedPreferences
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import com.audiencekit.TokenStore
import java.security.GeneralSecurityException
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/**
 * Keeps the session token in the app's private shared preferences, encrypted with an AES-GCM key that
 * never leaves the Android Keystore.
 *
 * The key needs no user authentication, so a background launch (location, push) can still make
 * authenticated calls. If the token can't be decrypted, e.g. after a backup was restored onto a new
 * device without its key, it is dropped and the person signs in again. Leave [preferencesName] out of
 * your app's backups.
 */
public class KeystoreTokenStore(
    context: Context,
    public val preferencesName: String = "com.audiencekit.session",
    public val keyAlias: String = "com.audiencekit.session",
) : TokenStore {
    private val preferences: SharedPreferences =
        context.applicationContext.getSharedPreferences(preferencesName, Context.MODE_PRIVATE)

    @Synchronized
    override fun loadToken(): String? {
        val stored = preferences.getString(TOKEN_KEY, null) ?: return null
        return try {
            val bytes = Base64.decode(stored, Base64.NO_WRAP)
            val cipher = Cipher.getInstance(TRANSFORMATION)
            cipher.init(Cipher.DECRYPT_MODE, key(), GCMParameterSpec(TAG_BITS, bytes, 0, IV_BYTES))
            cipher.doFinal(bytes, IV_BYTES, bytes.size - IV_BYTES).toString(Charsets.UTF_8)
        } catch (_: GeneralSecurityException) {
            preferences.edit().remove(TOKEN_KEY).apply()
            null
        } catch (_: IllegalArgumentException) {
            preferences.edit().remove(TOKEN_KEY).apply()
            null
        }
    }

    @Synchronized
    override fun saveToken(token: String) {
        val cipher = Cipher.getInstance(TRANSFORMATION)
        cipher.init(Cipher.ENCRYPT_MODE, key())
        val iv = cipher.iv
        check(iv.size == IV_BYTES) { "Unexpected GCM IV length ${iv.size}" }
        val sealed = iv + cipher.doFinal(token.toByteArray(Charsets.UTF_8))
        preferences.edit().putString(TOKEN_KEY, Base64.encodeToString(sealed, Base64.NO_WRAP)).apply()
    }

    @Synchronized
    override fun deleteToken() {
        preferences.edit().remove(TOKEN_KEY).remove(AUDIENCE_KEY).apply()
    }

    /** The audience the session was signed in on, as the sign-in JSON said. Not a secret, so kept in the clear. */
    @Synchronized
    override fun loadAudienceId(): String? = preferences.getString(AUDIENCE_KEY, null)

    @Synchronized
    override fun saveAudienceId(audienceId: String?) {
        preferences.edit().apply { if (audienceId == null) remove(AUDIENCE_KEY) else putString(AUDIENCE_KEY, audienceId) }.apply()
    }

    private fun key(): SecretKey {
        val keyStore = KeyStore.getInstance(ANDROID_KEYSTORE).apply { load(null) }
        (keyStore.getKey(keyAlias, null) as? SecretKey)?.let { return it }

        val generator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, ANDROID_KEYSTORE)
        generator.init(
            KeyGenParameterSpec.Builder(keyAlias, KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setKeySize(256)
                .build(),
        )
        return generator.generateKey()
    }

    private companion object {
        const val ANDROID_KEYSTORE = "AndroidKeyStore"
        const val TRANSFORMATION = "AES/GCM/NoPadding"
        const val TOKEN_KEY = "session-token"
        const val AUDIENCE_KEY = "session-audience-id"
        const val IV_BYTES = 12
        const val TAG_BITS = 128
    }
}
