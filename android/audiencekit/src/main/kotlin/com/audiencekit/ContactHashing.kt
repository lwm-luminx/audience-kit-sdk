package com.audiencekit

import java.security.MessageDigest
import java.text.Normalizer

// Friend matching from contacts, the part that happens on the phone (the API's doc/CONTACT_FRIEND_MATCHING.md,
// "Hashing and normalization spec"). A contact with a first name, a last name and a number becomes one SHA-256 hash
// per number; only the hashes leave the phone. The same as the Swift SDK's ContactHashing.swift, and both are tested
// against the same vectors.

/** One contact as read from the phone, before hashing. Never sent anywhere. */
public data class DeviceContact(
    val firstName: String,
    val lastName: String,
    /** Every number on the contact's card, as saved ("(206) 555-0142", "+44 20 7946 0958"). */
    val phoneNumbers: List<String>,
) {
    /** The name as the person saved it, for "In your contacts as Jordan Park". */
    val displayName: String
        get() = listOf(firstName, lastName).map { it.trim() }.filter { it.isNotEmpty() }.joinToString(" ")
}

/** What a phone sends for one check of its contacts, and what it keeps to itself. */
public data class ContactHashBatch(
    /** The hashes to send, shuffled, at most [ContactHashing.MAX_HASHES]. */
    val hashes: List<String>,
    /** How many contacts they cover, for "We checked 457 contacts". */
    val contactCount: Int,
    /** Contacts left out because they had no first name or no last name ("only a first name"). */
    val skippedWithoutFullName: Int = 0,
    /** Contacts left out because none of their numbers could be read as a full number. */
    val skippedWithoutNumber: Int = 0,
    /** Contacts left out because the check was already full. */
    val skippedOverLimit: Int = 0,
    /** The saved name behind each hash. Stays on the phone: it names a match ("In your contacts as Jordan Park"). */
    val names: Map<String, String> = emptyMap(),
)

/** Turns contacts into the hashes contact matching compares. Nothing here touches the network. */
public object ContactHashing {
    /** The most hashes one check may send (a contact with several numbers sends one per number). */
    public const val MAX_HASHES: Int = 10_000

    private val MARKS = Regex("\\p{Mn}")
    private val NOT_KEPT = Regex("[^a-z0-9]")

    /** A name as matching compares it: accents and case off, letters and digits only ("José-Luis" → "joseluis"). */
    public fun normalizeName(name: String): String =
        Normalizer.normalize(name, Normalizer.Form.NFKD).replace(MARKS, "").lowercase().replace(NOT_KEPT, "")

    /**
     * The hash for one contact and one of its numbers: lower-case hex SHA-256 of `first|last|+E164` with both names
     * normalized. [e164] is a number from [ContactHashing.e164].
     */
    public fun hash(firstName: String, lastName: String, e164: String): String =
        sha256("${normalizeName(firstName)}|${normalizeName(lastName)}|$e164")

    /**
     * A saved number in E.164 ("+12065550142"), or null when it can't be read as a full number. A number saved
     * without a country code takes the country of [region] (the phone's region, an ISO 3166 code like "US").
     */
    public fun e164(number: String, region: String?): String? {
        var text = number.trim()
        val end = text.indexOfFirst { it in ";,xX#" }
        if (end >= 0) text = text.substring(0, end)
        val international = text.trimStart(' ', '(').startsWith("+")
        val digits = buildString {
            for (character in text) if (Character.isDigit(character)) append(Character.digit(character, 10))
        }
        val full = (if (international) digits else fullNumber(digits, region)) ?: return null
        if (full.isEmpty() || full[0] == '0' || full.length !in 8..15) return null
        if (full.startsWith("1")) {
            // North America: a country digit, then ten digits whose area code and exchange never start with 0 or 1.
            if (full.length != 11 || full[1] < '2' || full[4] < '2') return null
        }
        return "+$full"
    }

    /**
     * The hashes for a set of contacts. A contact needs a first name, a last name and a readable number; every other
     * contact is counted in what was skipped. Stops adding contacts once the check is full.
     */
    public fun batch(contacts: List<DeviceContact>, region: String?, limit: Int = MAX_HASHES): ContactHashBatch {
        val names = LinkedHashMap<String, String>()
        var counted = 0
        var noName = 0
        var noNumber = 0
        var overLimit = 0
        for (contact in contacts) {
            val first = normalizeName(contact.firstName)
            val last = normalizeName(contact.lastName)
            if (first.isEmpty() || last.isEmpty()) {
                noName += 1
                continue
            }
            val numbers = contact.phoneNumbers.mapNotNull { e164(it, region) }.distinct()
            if (numbers.isEmpty()) {
                noNumber += 1
                continue
            }
            val new = numbers.map { sha256("$first|$last|$it") }.filter { it !in names }
            if (names.size + new.size > limit) {
                overLimit += 1
                continue
            }
            counted += 1
            for (hash in new) names[hash] = contact.displayName
        }
        return ContactHashBatch(names.keys.shuffled(), counted, noName, noNumber, overLimit, names)
    }

    /** The country calling code for a region ("US" → "1", "GB" → "44"), or null for one we don't know. */
    public fun callingCode(region: String?): String? = region?.let { CALLING_CODES[it.uppercase()] }

    /** Every region the SDK knows a calling code for, in alphabetical order, for a country picker. */
    public val regions: List<String> get() = CALLING_CODES.keys.sorted()

    /** Digits with their country code, from digits saved without a "+". */
    internal fun fullNumber(digits: String, region: String?): String? {
        val place = region?.uppercase() ?: return null
        val code = CALLING_CODES[place] ?: return null
        if (code == "1") {
            if (digits.startsWith("011")) return digits.drop(3)
            if (digits.length == 10) return "1$digits"
            return if (digits.length == 11 && digits.startsWith("1")) digits else null
        }
        val exit = if (place == "AU") "0011" else "00"
        if (digits.startsWith(exit)) return digits.drop(exit.length)
        return code + national(digits, place)
    }

    /** Digits without the prefix people dial inside the country (the "0" of 020 7946 0958). */
    internal fun national(digits: String, region: String): String = when (region) {
        "IT", "VA", "SM" -> digits
        "RU", "KZ" -> if (digits.length == 11 && digits.startsWith("8")) digits.drop(1) else digits
        "BY" -> if (digits.length == 11 && digits.startsWith("80")) digits.drop(2) else digits
        "HU" -> if (digits.startsWith("06")) digits.drop(2) else digits
        "LT" -> if (digits.length == 9 && (digits.startsWith("8") || digits.startsWith("0"))) digits.drop(1) else digits
        "MX" -> when {
            digits.length == 13 && (digits.startsWith("044") || digits.startsWith("045")) -> digits.drop(3)
            digits.length == 12 && digits.startsWith("01") -> digits.drop(2)
            else -> digits
        }
        else -> if (digits.startsWith("0")) digits.drop(1) else digits
    }

    internal fun sha256(text: String): String =
        MessageDigest.getInstance("SHA-256").digest(text.toByteArray(Charsets.UTF_8))
            .joinToString("") { "%02x".format(it) }

    internal val CALLING_CODES: Map<String, String> = mapOf(
        "AD" to "376", "AE" to "971", "AF" to "93", "AG" to "1", "AI" to "1", "AL" to "355",
        "AM" to "374", "AO" to "244", "AR" to "54", "AS" to "1", "AT" to "43", "AU" to "61",
        "AW" to "297", "AX" to "358", "AZ" to "994", "BA" to "387", "BB" to "1", "BD" to "880",
        "BE" to "32", "BF" to "226", "BG" to "359", "BH" to "973", "BI" to "257", "BJ" to "229",
        "BL" to "590", "BM" to "1", "BN" to "673", "BO" to "591", "BQ" to "599", "BR" to "55",
        "BS" to "1", "BT" to "975", "BW" to "267", "BY" to "375", "BZ" to "501", "CA" to "1",
        "CC" to "61", "CD" to "243", "CF" to "236", "CG" to "242", "CH" to "41", "CI" to "225",
        "CK" to "682", "CL" to "56", "CM" to "237", "CN" to "86", "CO" to "57", "CR" to "506",
        "CU" to "53", "CV" to "238", "CW" to "599", "CX" to "61", "CY" to "357", "CZ" to "420",
        "DE" to "49", "DJ" to "253", "DK" to "45", "DM" to "1", "DO" to "1", "DZ" to "213",
        "EC" to "593", "EE" to "372", "EG" to "20", "EH" to "212", "ER" to "291", "ES" to "34",
        "ET" to "251", "FI" to "358", "FJ" to "679", "FK" to "500", "FM" to "691", "FO" to "298",
        "FR" to "33", "GA" to "241", "GB" to "44", "GD" to "1", "GE" to "995", "GF" to "594",
        "GG" to "44", "GH" to "233", "GI" to "350", "GL" to "299", "GM" to "220", "GN" to "224",
        "GP" to "590", "GQ" to "240", "GR" to "30", "GT" to "502", "GU" to "1", "GW" to "245",
        "GY" to "592", "HK" to "852", "HN" to "504", "HR" to "385", "HT" to "509", "HU" to "36",
        "ID" to "62", "IE" to "353", "IL" to "972", "IM" to "44", "IN" to "91", "IO" to "246",
        "IQ" to "964", "IR" to "98", "IS" to "354", "IT" to "39", "JE" to "44", "JM" to "1",
        "JO" to "962", "JP" to "81", "KE" to "254", "KG" to "996", "KH" to "855", "KI" to "686",
        "KM" to "269", "KN" to "1", "KP" to "850", "KR" to "82", "KW" to "965", "KY" to "1",
        "KZ" to "7", "LA" to "856", "LB" to "961", "LC" to "1", "LI" to "423", "LK" to "94",
        "LR" to "231", "LS" to "266", "LT" to "370", "LU" to "352", "LV" to "371", "LY" to "218",
        "MA" to "212", "MC" to "377", "MD" to "373", "ME" to "382", "MF" to "590", "MG" to "261",
        "MH" to "692", "MK" to "389", "ML" to "223", "MM" to "95", "MN" to "976", "MO" to "853",
        "MP" to "1", "MQ" to "596", "MR" to "222", "MS" to "1", "MT" to "356", "MU" to "230",
        "MV" to "960", "MW" to "265", "MX" to "52", "MY" to "60", "MZ" to "258", "NA" to "264",
        "NC" to "687", "NE" to "227", "NF" to "672", "NG" to "234", "NI" to "505", "NL" to "31",
        "NO" to "47", "NP" to "977", "NR" to "674", "NU" to "683", "NZ" to "64", "OM" to "968",
        "PA" to "507", "PE" to "51", "PF" to "689", "PG" to "675", "PH" to "63", "PK" to "92",
        "PL" to "48", "PM" to "508", "PR" to "1", "PS" to "970", "PT" to "351", "PW" to "680",
        "PY" to "595", "QA" to "974", "RE" to "262", "RO" to "40", "RS" to "381", "RU" to "7",
        "RW" to "250", "SA" to "966", "SB" to "677", "SC" to "248", "SD" to "249", "SE" to "46",
        "SG" to "65", "SH" to "290", "SI" to "386", "SJ" to "47", "SK" to "421", "SL" to "232",
        "SM" to "378", "SN" to "221", "SO" to "252", "SR" to "597", "SS" to "211", "ST" to "239",
        "SV" to "503", "SX" to "1", "SY" to "963", "SZ" to "268", "TC" to "1", "TD" to "235",
        "TG" to "228", "TH" to "66", "TJ" to "992", "TK" to "690", "TL" to "670", "TM" to "993",
        "TN" to "216", "TO" to "676", "TR" to "90", "TT" to "1", "TV" to "688", "TW" to "886",
        "TZ" to "255", "UA" to "380", "UG" to "256", "US" to "1", "UY" to "598", "UZ" to "998",
        "VA" to "39", "VC" to "1", "VE" to "58", "VG" to "1", "VI" to "1", "VN" to "84",
        "VU" to "678", "WF" to "681", "WS" to "685", "XK" to "383", "YE" to "967", "YT" to "262",
        "ZA" to "27", "ZM" to "260", "ZW" to "263",
    )
}
