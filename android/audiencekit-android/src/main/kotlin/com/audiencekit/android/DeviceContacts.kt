package com.audiencekit.android

import android.content.Context
import android.provider.ContactsContract
import android.telephony.TelephonyManager
import com.audiencekit.ContactMatchNames
import com.audiencekit.DeviceContact
import com.audiencekit.FileContactMatchNameStore
import java.util.Locale

/**
 * Reads the phone's contacts for friend matching ([com.audiencekit.ContactHashing]). Only first names, last names
 * and phone numbers are read, and they go straight into hashing; nothing read here is sent or stored. The app
 * declares `android.permission.READ_CONTACTS` and asks for it before calling [read].
 */
public object DeviceContacts {
    /**
     * Every contact with its numbers as saved. Call it off the main thread, once `READ_CONTACTS` is granted; without
     * the permission it throws [SecurityException].
     */
    public fun read(context: Context): List<DeviceContact> {
        val resolver = context.contentResolver
        val names = HashMap<Long, Pair<String, String>>()
        resolver.query(
            ContactsContract.Data.CONTENT_URI,
            arrayOf(
                ContactsContract.Data.CONTACT_ID,
                ContactsContract.CommonDataKinds.StructuredName.GIVEN_NAME,
                ContactsContract.CommonDataKinds.StructuredName.FAMILY_NAME,
            ),
            "${ContactsContract.Data.MIMETYPE} = ?",
            arrayOf(ContactsContract.CommonDataKinds.StructuredName.CONTENT_ITEM_TYPE),
            null,
        )?.use { cursor ->
            while (cursor.moveToNext()) {
                val given = cursor.getString(1).orEmpty()
                val family = cursor.getString(2).orEmpty()
                val id = cursor.getLong(0)
                // A contact merged from several accounts has a name row for each; keep the fullest.
                val known = names[id]
                if (known == null || (known.second.isEmpty() && family.isNotEmpty())) names[id] = given to family
            }
        }
        val numbers = HashMap<Long, MutableList<String>>()
        resolver.query(
            ContactsContract.CommonDataKinds.Phone.CONTENT_URI,
            arrayOf(
                ContactsContract.CommonDataKinds.Phone.CONTACT_ID,
                ContactsContract.CommonDataKinds.Phone.NUMBER,
            ),
            null,
            null,
            null,
        )?.use { cursor ->
            while (cursor.moveToNext()) {
                val number = cursor.getString(1) ?: continue
                numbers.getOrPut(cursor.getLong(0)) { mutableListOf() }.add(number)
            }
        }
        return names.map { (id, name) -> DeviceContact(name.first, name.second, numbers[id].orEmpty()) }
    }

    /**
     * The phone's region for numbers saved without a country code: the SIM's country, else the network's, else the
     * phone's locale.
     */
    public fun region(context: Context): String? {
        val telephony = context.getSystemService(Context.TELEPHONY_SERVICE) as? TelephonyManager
        return listOf(telephony?.simCountryIso, telephony?.networkCountryIso, Locale.getDefault().country)
            .firstOrNull { !it.isNullOrBlank() }?.uppercase(Locale.ROOT)
    }
}

/**
 * What each match is saved as ([ContactMatchNames]), kept in the app's no-backup folder so the names stay on this
 * phone. One per audience.
 */
public fun contactMatchNames(context: Context, audienceId: String): ContactMatchNames =
    ContactMatchNames(
        FileContactMatchNameStore(
            java.io.File(context.noBackupFilesDir, "audiencekit-contact-match-names-$audienceId.json"),
        ),
    )
