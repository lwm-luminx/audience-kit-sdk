import Foundation

// Friend matching from contacts, the part that happens on the phone (the API's doc/CONTACT_FRIEND_MATCHING.md,
// "Hashing and normalization spec"). A contact with a first name, a last name and a number becomes one SHA-256 hash
// per number; only the hashes leave the phone. The Kotlin SDK's ContactHashing.kt does exactly the same, and both are
// tested against the same vectors.

/// One contact as read from the phone, before hashing. Never sent anywhere.
public struct DeviceContact: Sendable, Hashable {
    public let firstName: String
    public let lastName: String
    /// Every number on the contact's card, as saved ("(206) 555-0142", "+44 20 7946 0958").
    public let phoneNumbers: [String]

    public init(firstName: String, lastName: String, phoneNumbers: [String]) {
        self.firstName = firstName
        self.lastName = lastName
        self.phoneNumbers = phoneNumbers
    }

    /// The name as the person saved it, for "In your contacts as Jordan Park".
    public var displayName: String {
        [firstName, lastName].map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}

/// What a phone sends for one check of its contacts, and what it keeps to itself.
public struct ContactHashBatch: Sendable, Hashable {
    /// The hashes to send, shuffled, at most ``ContactHashing/maxHashes``.
    public let hashes: [String]
    /// How many contacts they cover, for "We checked 457 contacts".
    public let contactCount: Int
    /// Contacts left out because they had no first name or no last name ("only a first name").
    public let skippedWithoutFullName: Int
    /// Contacts left out because none of their numbers could be read as a full number.
    public let skippedWithoutNumber: Int
    /// Contacts left out because the check was already full.
    public let skippedOverLimit: Int
    /// The saved name behind each hash. Stays on the phone: it names a match ("In your contacts as Jordan Park").
    public let names: [String: String]

    public init(hashes: [String], contactCount: Int, skippedWithoutFullName: Int = 0, skippedWithoutNumber: Int = 0,
                skippedOverLimit: Int = 0, names: [String: String] = [:])
    {
        self.hashes = hashes
        self.contactCount = contactCount
        self.skippedWithoutFullName = skippedWithoutFullName
        self.skippedWithoutNumber = skippedWithoutNumber
        self.skippedOverLimit = skippedOverLimit
        self.names = names
    }
}

/// Turns contacts into the hashes contact matching compares. Nothing here touches the network.
public enum ContactHashing {
    /// The most hashes one check may send (a contact with several numbers sends one per number).
    public static let maxHashes = 10_000

    /// A name as matching compares it: accents and case off, letters and digits only ("José-Luis" → "joseluis").
    public static func normalizeName(_ name: String) -> String {
        var kept = String.UnicodeScalarView()
        for scalar in name.decomposedStringWithCompatibilityMapping.unicodeScalars
            where scalar.properties.generalCategory != .nonspacingMark
        {
            kept.append(scalar)
        }
        return String(String(kept).lowercased().unicodeScalars.filter {
            ($0.value >= 0x61 && $0.value <= 0x7A) || ($0.value >= 0x30 && $0.value <= 0x39)
        }.map(Character.init))
    }

    /// The hash for one contact and one of its numbers: lower-case hex SHA-256 of `first|last|+E164` with both names
    /// normalized. `e164` is a number from ``e164(_:region:)``.
    public static func hash(firstName: String, lastName: String, e164: String) -> String {
        SHA256Hex.digest("\(normalizeName(firstName))|\(normalizeName(lastName))|\(e164)")
    }

    /// A saved number in E.164 ("+12065550142"), or nil when it can't be read as a full number. A number saved
    /// without a country code takes the country of `region` (the phone's region, an ISO 3166 code like "US").
    public static func e164(_ number: String, region: String?) -> String? {
        var text = number.trimmingCharacters(in: .whitespacesAndNewlines)
        if let end = text.firstIndex(where: { ";,xX#".contains($0) }) { text = String(text[..<end]) }
        let international = text.drop { $0 == " " || $0 == "(" }.first == "+"
        let digits = String(text.unicodeScalars.compactMap { scalar -> Character? in
            guard scalar.properties.generalCategory == .decimalNumber,
                  let value = scalar.properties.numericValue else { return nil }
            return Character(String(Int(value)))
        })
        guard let full = international ? digits : fullNumber(digits, region: region) else { return nil }
        guard let first = full.first, first != "0", (8 ... 15).contains(full.count) else { return nil }
        if full.hasPrefix("1") {
            // North America: a country digit, then ten digits whose area code and exchange never start with 0 or 1.
            let national = Array(full.dropFirst())
            guard national.count == 10, national[0] >= "2", national[3] >= "2" else { return nil }
        }
        return "+\(full)"
    }

    /// The hashes for a set of contacts. A contact needs a first name, a last name and a readable number; every
    /// other contact is counted in what was skipped. Stops adding contacts once the check is full.
    public static func batch(_ contacts: [DeviceContact], region: String?, limit: Int = maxHashes) -> ContactHashBatch {
        var names: [String: String] = [:]
        var order: [String] = []
        var counted = 0, noName = 0, noNumber = 0, overLimit = 0
        for contact in contacts {
            let first = normalizeName(contact.firstName), last = normalizeName(contact.lastName)
            guard !first.isEmpty, !last.isEmpty else { noName += 1; continue }
            var numbers: [String] = []
            for number in contact.phoneNumbers {
                if let full = e164(number, region: region), !numbers.contains(full) { numbers.append(full) }
            }
            guard !numbers.isEmpty else { noNumber += 1; continue }
            let hashes = numbers.map { SHA256Hex.digest("\(first)|\(last)|\($0)") }
            let new = hashes.filter { names[$0] == nil }
            guard order.count + new.count <= limit else { overLimit += 1; continue }
            counted += 1
            for hash in new {
                names[hash] = contact.displayName
                order.append(hash)
            }
        }
        return ContactHashBatch(hashes: order.shuffled(), contactCount: counted, skippedWithoutFullName: noName,
                                skippedWithoutNumber: noNumber, skippedOverLimit: overLimit, names: names)
    }

    /// The country calling code for a region ("US" → "1", "GB" → "44"), or nil for one we don't know.
    public static func callingCode(region: String?) -> String? {
        region.flatMap { callingCodes[$0.uppercased()] }
    }

    /// Every region the SDK knows a calling code for, in alphabetical order, for a country picker.
    public static var regions: [String] { callingCodes.keys.sorted() }

    /// Digits with their country code, from digits saved without a "+".
    static func fullNumber(_ digits: String, region: String?) -> String? {
        guard let region = region?.uppercased(), let code = callingCodes[region] else { return nil }
        if code == "1" {
            if digits.hasPrefix("011") { return String(digits.dropFirst(3)) }
            if digits.count == 10 { return "1" + digits }
            return digits.count == 11 && digits.hasPrefix("1") ? digits : nil
        }
        let exit = region == "AU" ? "0011" : "00"
        if digits.hasPrefix(exit) { return String(digits.dropFirst(exit.count)) }
        return code + national(digits, region: region)
    }

    /// Digits without the prefix people dial inside the country (the "0" of 020 7946 0958).
    static func national(_ digits: String, region: String) -> String {
        switch region {
        case "IT", "VA", "SM":
            return digits
        case "RU", "KZ":
            return digits.count == 11 && digits.hasPrefix("8") ? String(digits.dropFirst()) : digits
        case "BY":
            return digits.count == 11 && digits.hasPrefix("80") ? String(digits.dropFirst(2)) : digits
        case "HU":
            return digits.hasPrefix("06") ? String(digits.dropFirst(2)) : digits
        case "LT":
            return digits.count == 9 && (digits.hasPrefix("8") || digits.hasPrefix("0")) ? String(digits.dropFirst())
                : digits
        case "MX":
            if digits.count == 13, digits.hasPrefix("044") || digits.hasPrefix("045") { return String(digits.dropFirst(3)) }
            if digits.count == 12, digits.hasPrefix("01") { return String(digits.dropFirst(2)) }
            return digits
        default:
            return digits.hasPrefix("0") ? String(digits.dropFirst()) : digits
        }
    }

    static let callingCodes: [String: String] = [
        "AD": "376", "AE": "971", "AF": "93", "AG": "1", "AI": "1", "AL": "355", "AM": "374", "AO": "244",
        "AR": "54", "AS": "1", "AT": "43", "AU": "61", "AW": "297", "AX": "358", "AZ": "994", "BA": "387",
        "BB": "1", "BD": "880", "BE": "32", "BF": "226", "BG": "359", "BH": "973", "BI": "257", "BJ": "229",
        "BL": "590", "BM": "1", "BN": "673", "BO": "591", "BQ": "599", "BR": "55", "BS": "1", "BT": "975",
        "BW": "267", "BY": "375", "BZ": "501", "CA": "1", "CC": "61", "CD": "243", "CF": "236", "CG": "242",
        "CH": "41", "CI": "225", "CK": "682", "CL": "56", "CM": "237", "CN": "86", "CO": "57", "CR": "506",
        "CU": "53", "CV": "238", "CW": "599", "CX": "61", "CY": "357", "CZ": "420", "DE": "49", "DJ": "253",
        "DK": "45", "DM": "1", "DO": "1", "DZ": "213", "EC": "593", "EE": "372", "EG": "20", "EH": "212",
        "ER": "291", "ES": "34", "ET": "251", "FI": "358", "FJ": "679", "FK": "500", "FM": "691", "FO": "298",
        "FR": "33", "GA": "241", "GB": "44", "GD": "1", "GE": "995", "GF": "594", "GG": "44", "GH": "233",
        "GI": "350", "GL": "299", "GM": "220", "GN": "224", "GP": "590", "GQ": "240", "GR": "30", "GT": "502",
        "GU": "1", "GW": "245", "GY": "592", "HK": "852", "HN": "504", "HR": "385", "HT": "509", "HU": "36",
        "ID": "62", "IE": "353", "IL": "972", "IM": "44", "IN": "91", "IO": "246", "IQ": "964", "IR": "98",
        "IS": "354", "IT": "39", "JE": "44", "JM": "1", "JO": "962", "JP": "81", "KE": "254", "KG": "996",
        "KH": "855", "KI": "686", "KM": "269", "KN": "1", "KP": "850", "KR": "82", "KW": "965", "KY": "1",
        "KZ": "7", "LA": "856", "LB": "961", "LC": "1", "LI": "423", "LK": "94", "LR": "231", "LS": "266",
        "LT": "370", "LU": "352", "LV": "371", "LY": "218", "MA": "212", "MC": "377", "MD": "373", "ME": "382",
        "MF": "590", "MG": "261", "MH": "692", "MK": "389", "ML": "223", "MM": "95", "MN": "976", "MO": "853",
        "MP": "1", "MQ": "596", "MR": "222", "MS": "1", "MT": "356", "MU": "230", "MV": "960", "MW": "265",
        "MX": "52", "MY": "60", "MZ": "258", "NA": "264", "NC": "687", "NE": "227", "NF": "672", "NG": "234",
        "NI": "505", "NL": "31", "NO": "47", "NP": "977", "NR": "674", "NU": "683", "NZ": "64", "OM": "968",
        "PA": "507", "PE": "51", "PF": "689", "PG": "675", "PH": "63", "PK": "92", "PL": "48", "PM": "508",
        "PR": "1", "PS": "970", "PT": "351", "PW": "680", "PY": "595", "QA": "974", "RE": "262", "RO": "40",
        "RS": "381", "RU": "7", "RW": "250", "SA": "966", "SB": "677", "SC": "248", "SD": "249", "SE": "46",
        "SG": "65", "SH": "290", "SI": "386", "SJ": "47", "SK": "421", "SL": "232", "SM": "378", "SN": "221",
        "SO": "252", "SR": "597", "SS": "211", "ST": "239", "SV": "503", "SX": "1", "SY": "963", "SZ": "268",
        "TC": "1", "TD": "235", "TG": "228", "TH": "66", "TJ": "992", "TK": "690", "TL": "670", "TM": "993",
        "TN": "216", "TO": "676", "TR": "90", "TT": "1", "TV": "688", "TW": "886", "TZ": "255", "UA": "380",
        "UG": "256", "US": "1", "UY": "598", "UZ": "998", "VA": "39", "VC": "1", "VE": "58", "VG": "1",
        "VI": "1", "VN": "84", "VU": "678", "WF": "681", "WS": "685", "XK": "383", "YE": "967", "YT": "262",
        "ZA": "27", "ZM": "260", "ZW": "263",
    ]
}
