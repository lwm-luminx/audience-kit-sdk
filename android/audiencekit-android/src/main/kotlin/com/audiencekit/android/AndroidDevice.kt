package com.audiencekit.android

import android.annotation.SuppressLint
import android.content.Context
import android.content.pm.PackageInfo
import android.content.pm.PackageManager
import android.os.Build
import android.provider.Settings
import com.audiencekit.AudienceKitClient
import com.audiencekit.AudienceKitConfiguration
import com.audiencekit.DeviceAttestor
import com.audiencekit.DeviceDescription
import com.audiencekit.FileGraphQLCache
import com.audiencekit.FileVisitedLocaleStore
import com.audiencekit.GraphQLCache
import com.audiencekit.GraphQLCachePolicy
import com.audiencekit.GraphQLMonitor
import com.audiencekit.HttpTransport
import com.audiencekit.UrlConnectionTransport
import com.audiencekit.VisitedLocales
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

/**
 * An [AudienceKitClient] that keeps its session in a [KeystoreTokenStore] and proves its sign-ins with Play Integrity
 * ([PlayIntegrityAttestor]; pass null to send none). A [monitor] (a `GraphQLOperationLog` for "Check the app", say) is
 * told about each GraphQL operation.
 */
public fun AudienceKitClient(
    context: Context,
    configuration: AudienceKitConfiguration,
    transport: HttpTransport = UrlConnectionTransport(),
    deviceAttestor: DeviceAttestor? = PlayIntegrityAttestor(context),
    monitor: GraphQLMonitor? = null,
    /** Keeps the last good answer to each query; [graphQLCache] gives one under the app's cache folder. */
    cache: GraphQLCache? = null,
    defaultCachePolicy: GraphQLCachePolicy = GraphQLCachePolicy.NetworkOnly,
): AudienceKitClient =
    AudienceKitClient(
        configuration, KeystoreTokenStore(context), transport, monitor = monitor, deviceAttestor = deviceAttestor,
        cache = cache, defaultCachePolicy = defaultCachePolicy,
    )

/** A [FileGraphQLCache] under the app's cache folder, which Android may clear when space runs low and never backs up. */
public fun graphQLCache(context: Context): FileGraphQLCache =
    FileGraphQLCache(java.io.File(context.cacheDir, "audiencekit-graphql"))

/**
 * The locales the person has been in lately ([VisitedLocales]), kept in the app's no-backup folder so they stay on
 * this phone. One list per audience.
 */
public fun visitedLocales(context: Context, audienceId: String): VisitedLocales =
    VisitedLocales(FileVisitedLocaleStore(java.io.File(context.noBackupFilesDir, "audiencekit-visited-locales-$audienceId.json")))

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
