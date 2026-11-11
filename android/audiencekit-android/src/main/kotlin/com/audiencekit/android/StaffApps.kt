package com.audiencekit.android

import android.content.Context
import android.content.pm.PackageManager
import com.audiencekit.StaffApp

/**
 * Which AudienceKit staff apps this phone has, for [com.audiencekit.CardFilter.installedStaffApps] and "Open in
 * Velvet" buttons. The app's manifest must list each package under `<queries>` (com.audiencekit.Velvet,
 * com.audiencekit.Velvet.next and so on); without it Android hides them and this says none. Nothing leaves the phone.
 */
public object StaffApps {
    public fun installed(context: Context): Set<StaffApp> = StaffApp.entries.filterTo(mutableSetOf()) {
        isInstalled(context, it)
    }

    public fun isInstalled(context: Context, app: StaffApp): Boolean =
        listOf(app.androidPackage, "${app.androidPackage}.next").any { packageName ->
            try {
                context.packageManager.getPackageInfo(packageName, 0)
                true
            } catch (_: PackageManager.NameNotFoundException) {
                false
            }
        }
}
