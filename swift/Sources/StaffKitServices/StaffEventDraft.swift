import Foundation
import AudienceCore

/// What an event or occurrence was when its editor opened, so a save sends only what changed: an occurrence of a
/// series is set apart from it only by real edits.
public struct StaffEventSnapshot: Sendable, Equatable {
    public var name: String
    public var description: String
    public var ticketURL: String
    public var start: Date?
    public var end: Date?
    public var tagIDs: Set<String>
    public var karaoke: StaffKaraokeDraft
    /// The series it is a date of, if any.
    public var seriesName: String?
    /// Whether that date was edited on its own and no longer follows its series.
    public var seriesOverride: Bool
    public init(name: String?, description: String?, ticketURL: String?, startAt: String?, endAt: String?,
                tags: [StaffEventTag]?, karaoke: StaffKaraokeNight?, seriesName: String?, seriesOverride: Bool) {
        self.name = name ?? ""
        self.description = description ?? ""
        self.ticketURL = ticketURL ?? ""
        start = parseInstant(startAt)
        end = parseInstant(endAt)
        tagIDs = Set((tags ?? []).map(\.id))
        self.karaoke = StaffKaraokeDraft(night: karaoke)
        self.seriesName = seriesName
        self.seriesOverride = seriesOverride
    }
}

/// A recurring series as its editor opened.
public struct StaffSeriesSnapshot: Sendable, Equatable {
    public var name: String
    public var description: String
    public var ticketURL: String
    public var rrule: String
    public var recurrenceText: String?
    public var startsOn: String
    public var startTime: String
    public var timeZone: String
    public var durationMinutes: Int?
    public var tagIDs: Set<String>
    public var karaoke: StaffKaraokeDraft
    public init(name: String, description: String?, ticketURL: String?, rrule: String, recurrenceText: String?, startsOn: String,
                startTime: String, timeZone: String, durationMinutes: Int?, tags: [StaffEventTag]?, karaoke: Bool?, karaokeSessionCode: String?) {
        self.name = name
        self.description = description ?? ""
        self.ticketURL = ticketURL ?? ""
        self.rrule = rrule
        self.recurrenceText = recurrenceText
        self.startsOn = startsOn
        self.startTime = startTime
        self.timeZone = timeZone
        self.durationMinutes = durationMinutes
        tagIDs = Set((tags ?? []).map(\.id))
        self.karaoke = StaffKaraokeDraft(enabled: karaoke ?? false, ownSessionCode: karaokeSessionCode)
    }
}

/// The fields the shared event editor (StaffKitUI's StaffEventEditor) edits, for one date or a recurring series,
/// in Velvet, Backstage and Focus alike. Each app adds its own fields (hosts, cover, image, curation) to what these build.
public struct StaffEventDraft: Sendable, Equatable {
    public var name = ""
    public var description = ""
    public var ticketURL = ""
    public var start: Date
    public var untilClose = true
    /// The time it ends; the date is the start's night (`end(in:)`).
    public var endTime: Date
    public var repeats = false
    public var recurrence = StaffRecurrence()
    /// Leave a series' rule as it is: one the editor can't show, or one they chose to keep.
    public var preserveRule = false
    /// The series' time zone. One date uses the editor's zone.
    public var timeZone: String
    public var karaoke = StaffKaraokeDraft()
    public var tagIDs: Set<String> = []
    /// Where a new event is: a venue's ID, or "" for the default (Backstage: the listing's home venue or TBA).
    public var venueID = ""
    /// The locale a new event to be announced is in, or "".
    public var localeID = ""

    /// A new event at 9 PM on `day` (tonight by default) in `zone`, or a new series starting then.
    public init(newOn day: Date? = nil, zone: TimeZone, recurring: Bool = false) {
        let calendar = venueCalendar(zone)
        start = calendar.date(bySettingHour: 21, minute: 0, second: 0, of: day ?? Date()) ?? Date()
        endTime = calendar.date(byAdding: .hour, value: 5, to: start) ?? start
        timeZone = zone.identifier
        repeats = recurring
    }

    /// An existing event or occurrence, in `zone`.
    public init(event: StaffEventSnapshot, zone: TimeZone) {
        let calendar = venueCalendar(zone)
        name = event.name
        description = event.description
        ticketURL = event.ticketURL
        start = event.start ?? calendar.date(bySettingHour: 21, minute: 0, second: 0, of: Date()) ?? Date()
        untilClose = event.end == nil
        endTime = event.end ?? calendar.date(byAdding: .hour, value: 5, to: start) ?? start
        timeZone = zone.identifier
        karaoke = event.karaoke
        tagIDs = event.tagIDs
    }

    /// An existing series, in its own zone (`fallbackZone` when that isn't one).
    public init(series: StaffSeriesSnapshot, fallbackZone: TimeZone) {
        let zone = TimeZone(identifier: series.timeZone) ?? fallbackZone
        name = series.name
        description = series.description
        ticketURL = series.ticketURL
        let begin = CivilDate.instant(on: series.startsOn, at: series.startTime, in: zone) ?? Date()
        start = begin
        untilClose = series.durationMinutes == nil
        endTime = series.durationMinutes.map { begin.addingTimeInterval(TimeInterval($0 * 60)) }
            ?? venueCalendar(zone).date(byAdding: .hour, value: 5, to: begin) ?? begin
        repeats = true
        let parsed = StaffRecurrence(rrule: series.rrule, zone: zone)
        recurrence = parsed ?? StaffRecurrence()
        preserveRule = parsed == nil
        timeZone = zone.identifier
        karaoke = series.karaoke
        tagIDs = series.tagIDs
    }

    /// The zone its times are in: the series' own when it repeats, `eventZone` for one date.
    public func zone(eventZone: TimeZone) -> TimeZone { repeats ? TimeZone(identifier: timeZone) ?? eventZone : eventZone }

    /// The end, on the start's night: an end time at or before the start is the next morning.
    public func end(in zone: TimeZone) -> Date? {
        guard !untilClose else { return nil }
        let calendar = venueCalendar(zone)
        let parts = calendar.dateComponents([.hour, .minute], from: endTime)
        guard var date = calendar.date(bySettingHour: parts.hour ?? 0, minute: parts.minute ?? 0, second: 0, of: start) else { return nil }
        if date <= start { date = calendar.date(byAdding: .day, value: 1, to: date) ?? date }
        return date
    }

    public var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    public var trimmedTicketURL: String { ticketURL.trimmingCharacters(in: .whitespacesAndNewlines) }
    /// Blank, or an https:// or http:// link.
    public var ticketURLIsValid: Bool {
        guard !trimmedTicketURL.isEmpty else { return true }
        guard let url = URL(string: trimmedTicketURL) else { return false }
        return ["https", "http"].contains(url.scheme?.lowercased() ?? "") && url.host != nil
    }
    /// Named, with a schedule the API can store.
    public var isValid: Bool { !trimmedName.isEmpty && (!repeats || preserveRule || recurrence.isValid) }

    /// Everything for a new event; only what changed from `original` for an existing one. Tags only when
    /// `includeTags` (audience admins). Karaoke goes separately (`setEventKaraoke`).
    public func eventFields(original: StaffEventSnapshot?, zone: TimeZone, includeTags: Bool) -> [String: GraphQLValue] {
        var fields: [String: GraphQLValue] = [:]
        let description = description.trimmingCharacters(in: .whitespacesAndNewlines)
        let end = end(in: zone)
        if original == nil || trimmedName != original?.name { fields["name"] = .string(trimmedName) }
        if original == nil || description != original?.description { fields["description"] = .string(description) }
        if original == nil || trimmedTicketURL != original?.ticketURL { fields["ticketUrl"] = .string(trimmedTicketURL) }
        if original == nil || original?.start != start { fields["startAt"] = .string(isoInstant(start)) }
        if original == nil || original?.end != end { fields["endAt"] = end.map { .string(isoInstant($0)) } ?? .null }
        if includeTags && (original == nil || tagIDs != original?.tagIDs) {
            fields["tagIds"] = .array(tagIDs.sorted().map(GraphQLValue.string))
        }
        return fields
    }

    /// A series' fields, all of them, karaoke included. Tags only when `includeTags`.
    public func seriesFields(includeTags: Bool, fallbackZone: TimeZone) -> [String: GraphQLValue] {
        let zone = TimeZone(identifier: timeZone) ?? fallbackZone
        var fields: [String: GraphQLValue] = [
            "name": .string(trimmedName), "description": .string(description.trimmingCharacters(in: .whitespacesAndNewlines)),
            "ticketUrl": .string(trimmedTicketURL),
            "startsOn": .string(CivilDate.string(from: start, in: zone)), "startTime": .string(CivilDate.timeString(from: start, in: zone)),
            "timeZone": .string(timeZone),
            "durationMinutes": end(in: zone).map { .int(Int($0.timeIntervalSince(start) / 60)) } ?? .null
        ]
        fields.merge(karaoke.seriesFields) { _, new in new }
        if !preserveRule { fields["rrule"] = .string(recurrence.rrule(zone: zone)) }
        if includeTags { fields["tagIds"] = .array(tagIDs.sorted().map(GraphQLValue.string)) }
        return fields
    }
}

extension TalentEvent {
    public var snapshot: StaffEventSnapshot {
        StaffEventSnapshot(name: name, description: description, ticketURL: ticketUrl, startAt: startAt, endAt: endAt, tags: tags,
                           karaoke: karaoke, seriesName: eventSeries?.name, seriesOverride: seriesOverride)
    }
}

extension TalentSeries {
    public var snapshot: StaffSeriesSnapshot {
        StaffSeriesSnapshot(name: name, description: description, ticketURL: ticketUrl, rrule: rrule, recurrenceText: recurrenceText,
                            startsOn: startsOn, startTime: startTime, timeZone: timeZone, durationMinutes: durationMinutes, tags: tags,
                            karaoke: karaoke, karaokeSessionCode: karaokeSessionCode)
    }
}

extension VenueEvent {
    public var snapshot: StaffEventSnapshot {
        StaffEventSnapshot(name: name, description: description, ticketURL: ticketUrl, startAt: startAt, endAt: endAt, tags: tags,
                           karaoke: karaoke, seriesName: eventSeries?.name, seriesOverride: seriesOverride)
    }
}

extension VenueSeries {
    public var snapshot: StaffSeriesSnapshot {
        StaffSeriesSnapshot(name: name, description: description, ticketURL: ticketUrl, rrule: rrule, recurrenceText: recurrenceText,
                            startsOn: startsOn, startTime: startTime, timeZone: timeZone, durationMinutes: durationMinutes, tags: tags,
                            karaoke: karaoke, karaokeSessionCode: karaokeSessionCode)
    }
}
