import Foundation

/// A calendar day with no time or zone: a birth date or an expiry as an ID prints it.
public struct DoorDay: Sendable, Hashable, Comparable, CustomStringConvertible {
    public let year: Int
    public let month: Int
    public let day: Int

    /// Nil unless it is a real date (no February 30th) in a year an ID could print.
    public init?(year: Int, month: Int, day: Int) {
        guard (1900...2200).contains(year), (1...12).contains(month), day >= 1 else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        guard let first = calendar.date(from: DateComponents(year: year, month: month, day: 1)),
              let days = calendar.range(of: .day, in: .month, for: first), days.contains(day) else { return nil }
        self.year = year; self.month = month; self.day = day
    }

    /// Today where the door is (the device's zone unless told otherwise).
    public static func today(in zone: TimeZone = .current, now: Date = Date()) -> DoorDay {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let parts = calendar.dateComponents([.year, .month, .day], from: now)
        return DoorDay(year: parts.year ?? 2000, month: parts.month ?? 1, day: parts.day ?? 1) ?? DoorDay(year: 2000, month: 1, day: 1)!
    }

    public static func < (a: DoorDay, b: DoorDay) -> Bool { (a.year, a.month, a.day) < (b.year, b.month, b.day) }

    /// yyyy-MM-dd, as the API writes dates.
    public var description: String { String(format: "%04d-%02d-%02d", year, month, day) }

    /// Whole years from this day to `on`.
    public func years(to on: DoorDay) -> Int {
        on.year - year - ((on.month, on.day) < (month, day) ? 1 : 0)
    }
}

/// The PDF417 barcode on the back of a North American driver's licence or ID card (the AAMVA DL/ID Card Design
/// Standard), read on the phone. It mirrors the API's `DoorId::Aamva` (audience_kit_api, doc/DOOR_ID_CHECKS.md) so the
/// door can:
///
/// - send the API only the fields a door may use (``minimized(_:)``): the home address, height, eye colour and every
///   other field stay on the phone;
/// - still answer when the API can't be reached (``DoorIDOnDevice``), with the same shape checks the API runs.
public struct AAMVABarcode: Sendable, Hashable {
    public let firstName: String?
    public let middleName: String?
    public let lastName: String?
    public let birthDate: DoorDay?
    public let expiresOn: DoorDay?
    public let issuedOn: DoorDay?
    /// male, female or unspecified.
    public let gender: String?
    /// Shown at the door, never kept for a scanned card.
    public let idNumber: String?
    /// The issuing state or province, e.g. "UT".
    public let issuer: String?
    /// USA or CAN.
    public let country: String
    /// DRIVERS_LICENSE or ID_CARD.
    public let documentKind: String
    /// Why the barcode doesn't look like a real ID's; empty when it does.
    public let problems: [String]

    public var name: String? {
        let parts = [firstName, middleName, lastName].compactMap { $0 }.filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }
    public var suspect: Bool { !problems.isEmpty }
    public func age(on day: DoorDay) -> Int? { birthDate?.years(to: day) }
    public func expired(on day: DoorDay) -> Bool { expiresOn.map { $0 < day } ?? false }

    /// The only data elements the door uses (Utah R82-4-101(3)(a)(iii): name, age, birth date, gender, ID number,
    /// expiry), plus what the shape check reads: issue date, issuing state, country.
    public static let doorElements: Set<String> = [
        "DAQ",                                    // ID number
        "DCS", "DAB", "DAC", "DCT", "DAD", "DAA", // names (v2+ split, v1 combined)
        "DBB", "DBA", "DBD",                      // born, expires, issued
        "DBC",                                    // gender
        "DAJ", "DCG",                             // issuing state, country
    ]

    /// Whether `text` is a licence barcode rather than a pass or some other code (the API's `Aamva.licence?`).
    public static func isLicence(_ text: String) -> Bool {
        let trimmed = text.drop(while: { $0 == " " || $0 == "\t" })
        return matches(header, String(trimmed)) || text.contains("ANSI 636")
    }

    /// Reads a licence barcode, as the camera or a scanner read it (control characters included). Nil when it isn't one.
    public static func read(_ text: String) -> AAMVABarcode? {
        guard isLicence(text) else { return nil }
        return Reader(text).card
    }

    /// The barcode with only ``doorElements`` left in it, in the layout the API reads: the header and subfile
    /// directory as scanned, then one element per line. Anything else on the card (address, height, weight, eye and
    /// hair colour, donor and veteran flags, the jurisdiction's own Z subfile) is dropped before it leaves the phone.
    /// Text that isn't a licence barcode comes back unchanged.
    public static func minimized(_ text: String) -> String {
        guard isLicence(text), let headerAt = text.range(of: "ANSI") ?? text.range(of: "AAMVA") else { return text }
        let leading = String(text[..<headerAt.lowerBound])
        let rest = String(text[headerAt.lowerBound...])
        let lines = rest.components(separatedBy: separators).filter { !$0.isEmpty }
        guard let headerLine = lines.first else { return text }
        var header = headerLine
        var elements: [String] = []
        if let start = firstMatch(subfileStart, headerLine) {
            header = String(headerLine[..<start.upperBound])
            elements.append(String(headerLine[start.upperBound...]))
        }
        for line in lines.dropFirst() { elements.append(stripDesignator(line)) }
        var kept: [String: String] = [:]
        for element in elements {
            let element = element.trimmingCharacters(in: .whitespaces)
            guard element.count >= 3 else { continue }
            let code = String(element.prefix(3))
            if doorElements.contains(code), kept[code] == nil { kept[code] = element }
        }
        // The API finds the first element by what follows the subfile designator (DAQ, DCS, DAA or DCT), so one of
        // those leads; the rest keep a fixed order.
        let order = ["DAQ", "DCS", "DAA", "DCT", "DAB", "DAC", "DAD", "DBB", "DBA", "DBD", "DBC", "DAJ", "DCG"]
        let body = order.compactMap { kept[$0] }
        return leading + header + body.joined(separator: "\n") + "\r"
    }

    // MARK: - Parsing (the same rules as DoorId::Aamva)

    static let separators = CharacterSet(charactersIn: "\n\r\u{1e}")
    /// Scanners differ in which of the leading control characters they keep, so only the words are required.
    static let header = regex(#"\A@?[\n\x{1E}\r]*(?:ANSI ?|AAMVA)"#)
    /// The issuer identification number (636xxx, 604xxx), the standard's version, the jurisdiction's version and the
    /// number of subfiles.
    static let preamble = regex(#"(?:ANSI |AAMVA)(\d{6})(\d{2})"#)
    /// Where the first data element starts on the header line: after the subfile designator (DL or ID).
    static let subfileStart = regex(#"\A.*?(?:DL|ID)(?=DAQ|DCA|DCS|DAA|DCT)"#)
    static let designator = regex(#"\A(?:DL|ID|Z[A-Z])(?=[A-Z]{3})"#)
    static let element = regex(#"\A([A-Z]{3})(.*)\z"#)
    static let idCardDirectory = regex(#"\d{2}ID\d{8}"#)
    static let licenceDirectory = regex(#"\d{2}DL\d{8}"#)
    static let eightDigits = regex(#"\d{8}"#)
    static let genders = ["1": "male", "M": "male", "2": "female", "F": "female", "9": "unspecified", "X": "unspecified"]
    static let notGiven: Set<String> = ["NONE", "UNAVL", "UNAVAILABLE"]

    static func regex(_ pattern: String) -> NSRegularExpression {
        // The patterns are constants; a typo is a programming error caught by the tests.
        try! NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators])
    }
    static func firstMatch(_ regex: NSRegularExpression, _ text: String) -> Range<String.Index>? {
        regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)).flatMap { Range($0.range, in: text) }
    }
    static func matches(_ regex: NSRegularExpression, _ text: String) -> Bool { firstMatch(regex, text) != nil }
    static func stripDesignator(_ line: String) -> String {
        guard let found = firstMatch(designator, line) else { return line }
        return String(line[found.upperBound...])
    }

    private struct Reader {
        let text: String
        var elements: [String: String] = [:]
        let iin: String?
        let version: Int?

        init(_ text: String) {
            self.text = text
            if let match = AAMVABarcode.preamble.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
               let iin = Range(match.range(at: 1), in: text), let version = Range(match.range(at: 2), in: text) {
                self.iin = String(text[iin]); self.version = Int(text[version])
            } else {
                iin = nil; version = nil
            }
            for raw in text.components(separatedBy: AAMVABarcode.separators) where !raw.isEmpty {
                var line = raw
                if line.contains("ANSI") || line.contains("AAMVA"), let start = AAMVABarcode.firstMatch(AAMVABarcode.subfileStart, line) {
                    line = String(line[start.upperBound...])
                }
                line = AAMVABarcode.stripDesignator(line).trimmingCharacters(in: .whitespaces)
                guard line.count >= 3, line.prefix(3).allSatisfy({ $0.isASCII && $0.isUppercase }) else { continue }
                let code = String(line.prefix(3))
                if elements[code] == nil { elements[code] = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces) }
            }
        }

        func value(_ code: String) -> String? {
            guard let found = elements[code], !found.isEmpty, !AAMVABarcode.notGiven.contains(found.uppercased()) else { return nil }
            return found
        }

        /// Version 1 has one name field ("LAST,FIRST,MIDDLE" or "LAST$FIRST$MIDDLE"); later ones split it.
        var fullNameParts: [String] {
            (value("DAA") ?? "").split(whereSeparator: { $0 == "," || $0 == "$" }).map { $0.trimmingCharacters(in: .whitespaces) }
        }
        func part(_ index: Int) -> String? { fullNameParts.indices.contains(index) ? fullNameParts[index] : nil }
        var firstName: String? {
            titleized(value("DAC") ?? value("DCT")?.split(whereSeparator: { $0 == "," || $0 == " " }).first.map(String.init) ?? part(1))
        }
        var middleName: String? { titleized(value("DAD") ?? part(2)) }
        var lastName: String? { titleized(value("DCS") ?? value("DAB") ?? part(0)) }

        func titleized(_ name: String?) -> String? {
            guard let name, !name.isEmpty else { return nil }
            var out = ""
            var startOfWord = true
            for character in name {
                if character == " " || character == "-" || character == "'" { out.append(character); startOfWord = true; continue }
                out += startOfWord ? character.uppercased() : character.lowercased()
                startOfWord = false
            }
            return out
        }

        var country: String { value("DCG")?.uppercased() ?? "USA" }

        /// US cards write MMDDCCYY; Canadian ones and some early cards write CCYYMMDD.
        func date(_ code: String) -> DoorDay? {
            guard let raw = value(code), let found = AAMVABarcode.firstMatch(AAMVABarcode.eightDigits, raw) else { return nil }
            let digits = Array(raw[found]).compactMap { $0.wholeNumberValue }
            func number(_ from: Int, _ count: Int) -> Int { digits[from..<(from + count)].reduce(0) { $0 * 10 + $1 } }
            let mdy = DoorDay(year: number(4, 4), month: number(0, 2), day: number(2, 2))
            let ymd = DoorDay(year: number(0, 4), month: number(4, 2), day: number(6, 2))
            return country == "CAN" ? (ymd ?? mdy) : (mdy ?? ymd)
        }

        var documentKind: String {
            AAMVABarcode.matches(AAMVABarcode.idCardDirectory, text) && !AAMVABarcode.matches(AAMVABarcode.licenceDirectory, text) ? "ID_CARD" : "DRIVERS_LICENSE"
        }

        func problems(today: DoorDay) -> [String] {
            var found: [String] = []
            let trimmed = String(text.drop(while: { $0 == " " || $0 == "\t" }))
            if !AAMVABarcode.matches(AAMVABarcode.header, trimmed) { found.append("The barcode doesn’t start like an ID’s") }
            if !(iin.map { $0.hasPrefix("636") || $0.hasPrefix("604") } ?? false) { found.append("The barcode’s issuer number isn’t an ID issuer’s") }
            if !(version.map { (0...11).contains($0) } ?? false) { found.append("The barcode’s format version isn’t one IDs use") }
            let hasName = lastName != nil || !fullNameParts.isEmpty
            if !(["DAQ", "DBB", "DBA"].allSatisfy { !(elements[$0] ?? "").isEmpty } && hasName) {
                found.append("The barcode is missing fields every ID has")
            }
            let born = date("DBB"), issued = date("DBD"), expires = date("DBA")
            if value("DBB") != nil && born == nil { found.append("The birth date isn’t a real date") }
            if value("DBA") != nil && expires == nil { found.append("The expiry date isn’t a real date") }
            if let born, !((issued.map { $0 >= born } ?? true) && (expires.map { $0 > born } ?? true) && born <= today) {
                found.append("The dates are in an impossible order")
            }
            if let issuer = value("DAJ"), !(issuer.count == 2 && issuer.allSatisfy { $0.isASCII && $0.isLetter }) {
                found.append("The issuing state isn’t a state or province code")
            }
            return found
        }

        var card: AAMVABarcode { card(today: .today()) }

        func card(today: DoorDay) -> AAMVABarcode {
            AAMVABarcode(firstName: firstName, middleName: middleName, lastName: lastName, birthDate: date("DBB"),
                         expiresOn: date("DBA"), issuedOn: date("DBD"), gender: value("DBC").flatMap { AAMVABarcode.genders[$0.trimmingCharacters(in: .whitespaces).uppercased()] },
                         idNumber: value("DAQ"), issuer: value("DAJ")?.uppercased(), country: country, documentKind: documentKind,
                         problems: problems(today: today))
        }
    }

    /// Reads with a fixed "today", for tests and for a door that knows its venue's zone.
    public static func read(_ text: String, today: DoorDay) -> AAMVABarcode? {
        guard isLicence(text) else { return nil }
        return Reader(text).card(today: today)
    }
}

/// An ID checked on the phone alone, because the API couldn't be reached. Nothing is logged: where the law asks for
/// a log (Utah), the door types the ID in once it's back online.
public struct DoorIDOnDevice: Sendable, Hashable {
    /// OK, UNDER_AGE, EXPIRED or SUSPECT, as the API would answer.
    public let outcome: String
    public let message: String
    public let card: AAMVABarcode
    public var admitted: Bool { outcome == "OK" }

    /// The same verdict as the API's `DoorId::Check`: a fake-looking barcode, then expiry, then age.
    public init?(barcode: String, drinkingAge: Int = 21, today: DoorDay = .today()) {
        guard let card = AAMVABarcode.read(barcode, today: today) else { return nil }
        self.card = card
        let age = card.age(on: today)
        let who = [card.name, age.map(String.init)].compactMap { $0 }.joined(separator: ", ")
        if card.suspect {
            outcome = "SUSPECT"
            message = "Possible fake ID: \(card.problems[0]). Keep the ID and call the police."
        } else if card.expired(on: today) {
            outcome = "EXPIRED"
            message = "Expired \(card.expiresOn.map(\.description) ?? "") · \(who)"
        } else if age == nil || age! < drinkingAge {
            outcome = "UNDER_AGE"
            message = "Under \(drinkingAge) · \(who)"
        } else {
            outcome = "OK"
            message = "OK · \(who)"
        }
    }
}
