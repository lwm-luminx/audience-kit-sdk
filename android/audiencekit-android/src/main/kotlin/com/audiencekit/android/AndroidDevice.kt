package com.audiencekit.android

import android.annotation.SuppressLint
import android.content.Context
import android.content.pm.PackageInfo
import android.content.pm.PackageManager
import android.os.Build
import android.provider.Settings
import com.audiencekit.AudienceKitClient
import com.audiencekit.AudienceKitConfiguration
import com.audiencekit.DeviceDescription
import com.audiencekit.HttpTransport
import com.audiencekit.UrlConnectionTransport
import java.util.UUID

/**
 * This device and app, for [AudienceKitClient.signIn]: the install's [identifier], the hardware
 * model, and the app's version name and version code.
 */
public fun DeviceDescription.Companion.current(
    context: Context,
    identifier: String = installationIdentifier(context),
): DeviceDescription {
    val packageInfo = runCatching { context.packageInfo() }.getOrNull()
    return DeviceDescription(
        identifier = identifier,
        model = deviceModel(),
        version = packageInfo?.versionName,
        build = packageInfo?.let(::versionCode)?.toString(),
    )
}

/**
 * A stable identifier for this install: `Settings.Secure.ANDROID_ID`, which is scoped to the app's
 * signing key and the user, like `identifierForVendor` on iOS. Falls back to a random ID kept in the
 * app's preferences.
 */
@SuppressLint("HardwareIds")
public fun installationIdentifier(context: Context): String {
    Settings.Secure.getString(context.contentResolver, Settings.Secure.ANDROID_ID)
        ?.takeIf { it.isNotBlank() }
        ?.let { return it }

    val preferences = context.applicationContext.getSharedPreferences("com.audiencekit.device", Context.MODE_PRIVATE)
    return preferences.getString("identifier", null) ?: UUID.randomUUID().toString().also {
        preferences.edit().putString("identifier", it).apply()
    }
}

/** An [AudienceKitClient] that keeps its session in a [KeystoreTokenStore]. */
public fun AudienceKitClient(
    context: Context,
    configuration: AudienceKitConfiguration,
    transport: HttpTransport = UrlConnectionTransport(),
): AudienceKitClient = AudienceKitClient(configuration, KeystoreTokenStore(context), transport)

private fun deviceModel(): String {
    val manufacturer = Build.MANUFACTURER.replaceFirstChar { it.uppercase() }
    return if (Build.MODEL.startsWith(Build.MANUFACTURER, ignoreCase = true)) Build.MODEL else "$manufacturer ${Build.MODEL}"
}

private fun Context.packageInfo(): PackageInfo =
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
        packageManager.getPackageInfo(packageName, PackageManager.PackageInfoFlags.of(0))
    } else {
        @Suppress("DEPRECATION")
        packageManager.getPackageInfo(packageName, 0)
    }

private fun versionCode(info: PackageInfo): Long =
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
        info.longVersionCode
    } else {
        @Suppress("DEPRECATION")
        info.versionCode.toLong()
    }
