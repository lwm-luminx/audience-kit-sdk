import Foundation

/// A detail of a venue that a merge can take from the duplicate instead of the venue kept: the API's
/// `VenueMergeField` (`mergeVenue(takeFromSource:)`). Details not taken stay the kept venue's, filled from the
/// duplicate where the kept venue has none.
public enum VenueMergeField: String, Codable, Sendable, CaseIterable, Hashable, Identifiable {
    case name = "NAME"
    case description = "DESCRIPTION"
    case website = "WEBSITE"
    case phone = "PHONE"
    case photo = "PHOTO"
    case place = "PLACE"
    case locale = "LOCALE"
    case facebookPage = "FACEBOOK_PAGE"
    case hidden = "HIDDEN"
    case visibility = "VISIBILITY"

    public var id: String { rawValue }

    /// The choices a phone's merge form offers, in its order; the rest stay the kept venue's.
    public static let offered: [VenueMergeField] = [.name, .description, .website, .photo, .place, .locale]

    /// A row's label in the merge form.
    public var title: String {
        switch self {
        case .name: "Name"
        case .description: "Description"
        case .website: "Website"
        case .phone: "Phone"
        case .photo: "Photo"
        case .place: "Location"
        case .locale: "Locale"
        case .facebookPage: "Facebook Page"
        case .hidden: "Hidden"
        case .visibility: "Visibility"
        }
    }
}

/// Why the API thinks two venues are the same place: `VenueDuplicateReason`.
public enum VenueDuplicateReason: String, Codable, Sendable, CaseIterable, Hashable {
    case samePlace = "SAME_PLACE"
    case sameName = "SAME_NAME"
    case nearbySimilarName = "NEARBY_SIMILAR_NAME"
    /// A reason this SDK doesn't know yet.
    case unknown

    public init(from decoder: Decoder) throws {
        self = VenueDuplicateReason(rawValue: try decoder.singleValueContainer().decode(String.self)) ?? .unknown
    }

    /// In words, for the pair's subtitle.
    public var title: String {
        switch self {
        case .samePlace: "Same Google place"
        case .sameName: "Same name in the same locale"
        case .nearbySimilarName: "Close by with a similar name"
        case .unknown: "Looks alike"
        }
    }
}

/// Two venues the API thinks are one place (`venues { duplicates }` on the staff endpoint, administrators only): the
/// one it suggests keeping and the one to merge into it.
public struct VenueDuplicate: Decodable, Sendable, Hashable, Identifiable {
    public struct Venue: Decodable, Sendable, Hashable {
        public let id: String
        public let name: String?
        public init(id: String, name: String?) { self.id = id; self.name = name }
    }

    /// On Google, with more events, or older.
    public let keep: Venue
    public let merge: Venue
    public let reasons: [VenueDuplicateReason]
    /// Meters apart; nil when either has no location.
    public let distance: Int?

    public init(keep: Venue, merge: Venue, reasons: [VenueDuplicateReason], distance: Int? = nil) {
        self.keep = keep; self.merge = merge; self.reasons = reasons; self.distance = distance
    }

    public var id: String { keep.id + ":" + merge.id }

    /// "Same Google place · 40 m apart".
    public var reasonLine: String {
        var parts = reasons.map(\.title)
        if let distance { parts.append("\(distance) m apart") }
        return parts.joined(separator: " · ")
    }
}

/// The GraphQL for deleting an audience's venues and people and merging its venues from a staff app (Focus), shared so no app writes its
/// own, and the same on Android word for word. They run on the staff endpoint (`# endpoint: staff`), which this SDK
/// doesn't call: StaffKit's session sends them with these variables and decodes the responses. The API decides who
/// may: each needs `venues:write:*`.
public enum ListingCuration {
    public static let deleteMutation = """
        # endpoint: staff
        mutation FocusDeleteVenue($id: ID!) { deleteVenue(input: { id: $id }) { deletedId } }
        """

    /// Removes a person (a performer's listing) from the audience; needs `people:write:*`. Decode ``DeleteResponse``.
    public static let deletePersonMutation = """
        # endpoint: staff
        mutation FocusDeletePerson($id: ID!) { deletePerson(input: { id: $id }) { deletedId } }
        """

    public static let mergeMutation = """
        # endpoint: staff
        mutation FocusMergeVenue($sourceId: ID!, $destinationId: ID!, $takeFromSource: [VenueMergeField!]) { \
        mergeVenue(input: { sourceId: $sourceId, destinationId: $destinationId, takeFromSource: $takeFromSource }) { \
        deletedId venue { id name } moved { kind count } } }
        """

    public static let duplicatesQuery = """
        # endpoint: staff
        query FocusVenueDuplicates { venues { duplicates { distance reasons keep { id name } merge { id name } } } }
        """

    public static let dismissDuplicateMutation = """
        # endpoint: staff
        mutation FocusDismissVenueDuplicate($input: VenueDuplicateDismissInput!) { \
        dismissVenueDuplicate(input: $input) { clientMutationId } }
        """

    /// The variables for ``deleteMutation`` and ``deletePersonMutation``.
    public static func deleteVariables(id: String) -> [String: GraphQLValue] { ["id": .string(id)] }

    /// The variables for ``mergeMutation``: `source` is merged into `destination` and deleted.
    public static func mergeVariables(sourceID: String, destinationID: String,
                                      takeFromSource: [VenueMergeField] = []) -> [String: GraphQLValue] {
        let fields = VenueMergeField.allCases.filter { takeFromSource.contains($0) }
        return ["sourceId": .string(sourceID), "destinationId": .string(destinationID),
                "takeFromSource": .array(fields.map { .string($0.rawValue) })]
    }

    /// The variables for ``dismissDuplicateMutation``: the pair isn't one place.
    public static func dismissVariables(_ duplicate: VenueDuplicate, note: String? = nil) -> [String: GraphQLValue] {
        var input: [String: GraphQLValue] = ["venueIds": .array([.string(duplicate.keep.id), .string(duplicate.merge.id)])]
        if let note = note?.trimmingCharacters(in: .whitespacesAndNewlines), !note.isEmpty { input["note"] = .string(note) }
        return ["input": .object(input)]
    }

    /// ``deleteMutation``'s and ``deletePersonMutation``'s answer.
    public struct DeleteResponse: Decodable, Sendable {
        struct Payload: Decodable, Sendable { let deletedId: String }
        let deleteVenue: Payload?
        let deletePerson: Payload?
        public var deletedID: String? { deleteVenue?.deletedId ?? deletePerson?.deletedId }
    }

    /// ``mergeMutation``'s answer.
    public struct MergeResponse: Decodable, Sendable {
        public struct Moved: Decodable, Sendable, Hashable { public let kind: String; public let count: Int }
        struct Payload: Decodable, Sendable { let deletedId: String; let venue: VenueDuplicate.Venue; let moved: [Moved] }
        let mergeVenue: Payload?
        public var deletedID: String? { mergeVenue?.deletedId }
        public var venue: VenueDuplicate.Venue? { mergeVenue?.venue }
        public var moved: [Moved] { mergeVenue?.moved ?? [] }
        /// How many records moved to the kept venue.
        public var movedCount: Int { moved.reduce(0) { $0 + $1.count } }
    }

    /// ``duplicatesQuery``'s answer; empty for someone who isn't allowed to see them.
    public struct DuplicatesResponse: Decodable, Sendable {
        struct Venues: Decodable, Sendable { let duplicates: [VenueDuplicate]? }
        let venues: Venues?
        public var duplicates: [VenueDuplicate] { venues?.duplicates ?? [] }
    }
}

/// The words around deleting venues and people and merging venues, the same on Android and as the web console's.
public enum ListingCurationCopy {
    public static let delete = "Delete venue"
    public static let deletePerson = "Delete person"
    public static let deleteConfirm = "Delete"
    public static let merge = "Merge with another venue"
    public static let mergeConfirm = "Merge venues"
    public static let mergeWith = "Merge with"
    public static let keep = "Keep"
    public static let mergeAway = "Merge away"
    public static let swap = "Swap"
    public static let takeFromOther = "Use the merged venue's"
    public static let mergeDetail = "Events, series, lineups, chat and rooms, posts, tags, staff and access move to "
        + "the venue kept. What both have once, like a cover night or a back-of-house room, is combined. The venue "
        + "merged away is deleted."
    public static let duplicates = "Possible duplicates"
    public static let notDuplicate = "Not a duplicate"
    public static let noDuplicates = "No likely duplicates."

    /// The delete confirmation's title.
    public static func deleteTitle(_ name: String) -> String { "Delete \(name)?" }

    /// The delete confirmation's message.
    public static func deleteDetail(_ name: String) -> String {
        "\(name) and all of its events will be deleted. To keep them, hide the venue instead. This cannot be undone."
    }

    /// The person delete confirmation's message.
    public static func deletePersonDetail(_ name: String) -> String {
        "\(name) will be removed from the audience. This cannot be undone."
    }

    /// The merge confirmation's title.
    public static func mergeTitle(from: String, into: String) -> String { "Merge \(from) into \(into)?" }

    /// After a delete.
    public static func deleted(_ name: String) -> String { "\(name) is deleted." }

    /// After a merge.
    public static func merged(from: String, into: String) -> String { "\(from) is merged into \(into)." }
}
