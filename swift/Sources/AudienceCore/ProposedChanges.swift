import Foundation

/// What a reviewer decides about a proposed change: the API's `SubmissionDecisionAction` (`decideSubmission`).
public enum ProposedChangeAction: String, Codable, Sendable, CaseIterable, Hashable {
    /// Apply it as proposed.
    case approve = "APPROVE"
    /// Apply the reviewer's version instead (a social profile's other handle).
    case editApprove = "EDIT_APPROVE"
    /// Ask the venue's staff to confirm it first.
    case needsVenue = "NEEDS_VENUE"
    /// Don't apply it; needs a reason, which whoever suggested it sees.
    case reject = "REJECT"
}

/// A change waiting for a person before it reaches a live listing, the web console's Proposed changes: a profile an
/// import wasn't sure of, a member's correction, a missing venue or event, a closure, a tag or a tribe. The API's
/// `Submission` (audience_kit_api doc/CONTRIBUTIONS.md), read on the staff endpoint by audience administrators.
public struct ProposedChange: Decodable, Sendable, Identifiable, Hashable {
    /// A listing it's about: a person, venue, event or locale.
    public struct Listing: Decodable, Sendable, Hashable {
        public let id: String
        public let name: String?
        public init(id: String, name: String?) { self.id = id; self.name = name }
    }

    /// What an Instagram account looks like, read in the background (`SocialProfilePreview`).
    public struct Profile: Decodable, Sendable, Hashable, Identifiable {
        public let username: String
        /// pending, ready, failed or unavailable.
        public let status: String
        public let name: String?
        public let pictureUrl: String?
        public let biography: String?
        public let followersCount: Int?
        public let postsCount: Int?
        public let imageUrls: [String]
        public let error: String?
        public var id: String { username }
        public var isPending: Bool { status == "pending" }

        public init(username: String, status: String = "ready", name: String? = nil, pictureUrl: String? = nil,
                    biography: String? = nil, followersCount: Int? = nil, postsCount: Int? = nil,
                    imageUrls: [String] = [], error: String? = nil) {
            self.username = username; self.status = status; self.name = name; self.pictureUrl = pictureUrl
            self.biography = biography; self.followersCount = followersCount; self.postsCount = postsCount
            self.imageUrls = imageUrls; self.error = error
        }
    }

    /// What researching it found.
    public struct Research: Decodable, Sendable, Hashable {
        public let summary: String?
        /// approve, reject, needs_venue or unsure.
        public let recommendation: String?
    }

    /// A decision on it.
    public struct Decision: Decodable, Sendable, Hashable {
        public let action: String
        public let reason: String?
        public let createdAt: String
        public let reviewer: Listing?
    }

    /// One field it changes: from what (nil when the listing has no such field yet) to what.
    public struct Change: Sendable, Hashable, Identifiable {
        public let field: String
        public let from: String?
        public let to: String
        public init(field: String, from: String?, to: String) { self.field = field; self.from = from; self.to = to }
        public var id: String { field }
        /// "Opening hours" for `opening_hours`.
        public var title: String {
            let words = field.replacingOccurrences(of: "_", with: " ")
            return words.prefix(1).uppercased() + words.dropFirst()
        }
    }

    public let id: String
    /// `SubmissionKind`: SOCIAL_LINK, CORRECTION, MISSING_VENUE, MISSING_EVENT, CLOSED, TAG_SUGGESTION, …
    public let kind: String
    /// `SubmissionStatus`: SUBMITTED, RESEARCHING, IN_REVIEW, NEEDS_VENUE, APPROVED, REJECTED, MERGED.
    public let status: String
    /// low, normal or high.
    public let risk: String
    public let createdAt: String
    public let decidedAt: String?
    public let proposed: GraphQLValue
    public let current: GraphQLValue
    /// For a social profile: the handles found, the proposed one first.
    public let choices: [String]
    public let choiceProfiles: [Profile]
    /// What the submitter wrote.
    public let body: String?
    /// Links and photos: [{kind, url, photoId, photoUrl}].
    public let evidence: GraphQLValue
    /// attendee, talent, venue_staff, admin or system.
    public let submitterRole: String
    public let reporterCount: Int
    public let disputeCount: Int
    public let person: Listing?
    public let venue: Listing?
    public let event: Listing?
    public let locale: Listing?
    public let research: [Research]
    public let decisions: [Decision]

    public var isSocialLink: Bool { kind == "SOCIAL_LINK" }
    public var isHighRisk: Bool { risk == "high" }
    public var isOpen: Bool { decidedAt == nil }
    /// Still waiting on a reviewer here: open, and not handed to the venue's staff.
    public var isWaiting: Bool { isOpen && status != "NEEDS_VENUE" }
    /// Whether "Ask the venue" makes sense: a change about a venue, not a social profile.
    public var canAskVenue: Bool { isWaiting && !isSocialLink && venue != nil }

    /// For a social profile: the network (instagram, tiktok, …).
    public var provider: String? { proposed.member("provider")?.textValue }
    /// For a social profile: the handle it proposes.
    public var proposedHandle: String? { proposed.member("handle")?.textValue }
    /// For a social profile: the listing's handle now.
    public var currentHandle: String? { current.member("handle")?.textValue }
    /// For a social profile: the handles found that have no profile card, which get their own button.
    public var uncardedChoices: [String] {
        let carded = Set(choiceProfiles.map(\.username))
        return choices.filter { !carded.contains($0) }
    }
    /// Whether any profile is still being read, so the queue should look again shortly.
    public var isReadingProfiles: Bool { choiceProfiles.contains(where: \.isPending) }

    /// What it would change, field by field, in the API's order.
    public var changes: [Change] {
        guard case .object(let proposed) = proposed else { return [] }
        let current: [String: GraphQLValue] = if case .object(let fields) = self.current { fields } else { [:] }
        return proposed.keys.sorted().map { field in
            Change(field: field, from: current[field].map(Self.show), to: Self.show(proposed[field] ?? .null))
        }
    }

    /// The evidence's links, to look at.
    public var evidenceLinks: [URL] {
        guard case .array(let items) = evidence else { return [] }
        return items.compactMap { item in
            (item.member("url")?.textValue ?? item.member("photoUrl")?.textValue).flatMap(URL.init(string:))
        }
    }

    /// The listing it's about.
    public var subject: Listing? { person ?? event ?? venue }

    /// "Instagram for Murray Hill", "Correction: The Wildrose".
    public var title: String {
        let about = subject?.name
        if isSocialLink {
            return "\(ProposedChanges.networkTitle(provider) ?? "Profile") for \(about ?? "a listing")"
        }
        let kindTitle = ProposedChanges.kindTitle(kind)
        let name = about ?? proposed.member("name")?.textValue ?? proposed.member("tribe_name")?.textValue
        return name.map { "\(kindTitle): \($0)" } ?? kindTitle
    }

    /// "From an import · Seattle", "From 3 people".
    public var source: String {
        let who = reporterCount > 1 ? "\(reporterCount) people" : ProposedChanges.roleTitle(submitterRole)
        return ["From \(who)", locale?.name].compactMap { $0 }.joined(separator: " · ")
    }

    /// The status in words: "In review", "Asked the venue", "Approved".
    public var statusTitle: String { ProposedChanges.statusTitle(status) }

    /// The latest research's summary, with its recommendation: "Research (needs venue): …".
    public var researchLine: String? {
        guard let latest = research.last, let summary = latest.summary, !summary.isEmpty else { return nil }
        let recommendation = latest.recommendation.map { " (\($0.replacingOccurrences(of: "_", with: " ")))" } ?? ""
        return "Research\(recommendation): \(summary)"
    }

    /// Who decided and why: "Approved by Rick M.", "Rejected by Rick M. · Not a match".
    public var decisionLine: String? {
        guard decidedAt != nil, let decision = decisions.last else { return nil }
        let line = "\(statusTitle) by \(decision.reviewer?.name ?? "an admin")"
        guard let reason = decision.reason, !reason.isEmpty else { return line }
        return "\(line) · \(reason)"
    }

    /// The profile page for `handle` on this change's network, where the network has one.
    public func profileURL(_ handle: String) -> URL? { ProposedChanges.profileURL(provider: provider, handle: handle) }

    private static func show(_ value: GraphQLValue) -> String {
        switch value {
        case .null: "—"
        case .string(let text): text.isEmpty ? "—" : text
        case .bool(let flag): flag ? "Yes" : "No"
        case .int(let number): String(number)
        case .double(let number): String(number)
        case .array(let items): items.map(show).joined(separator: ", ")
        case .object:
            (try? String(data: JSONEncoder().encode(value), encoding: .utf8)) ?? "…"
        }
    }
}

/// A performer's headshot found elsewhere (their own Instagram posts, or a worker's find) that nobody has approved
/// yet: `headshotsToReview`. Approving lets posters use it; removing drops it.
public struct HeadshotToReview: Decodable, Sendable, Identifiable, Hashable {
    public let id: String
    public let url: String
    /// instagram or worker.
    public let origin: String
    public let sourceUrl: String?
    public let person: ProposedChange.Listing

    public init(id: String, url: String, origin: String, sourceUrl: String?, person: ProposedChange.Listing) {
        self.id = id; self.url = url; self.origin = origin; self.sourceUrl = sourceUrl; self.person = person
    }

    /// "From their Instagram" or "Found by a worker".
    public var originTitle: String { origin == "instagram" ? "From their Instagram" : "Found by a worker" }
}

/// Two venues someone said are different places (`venues { dismissedDuplicates }`), kept so the call can be undone.
public struct VenueDuplicateDismissal: Decodable, Sendable, Identifiable, Hashable {
    public let id: String
    public let active: Bool
    public let note: String?
    public let dismissedAt: String
    public let dismissedBy: ProposedChange.Listing?
    public let reasons: [VenueDuplicateReason]
    /// Why they look the same today; empty when they no longer do.
    public let currentReasons: [VenueDuplicateReason]
    public let venues: [VenueDuplicate.Venue]

    /// "The Edge and Edge NYC".
    public var title: String {
        venues.map { $0.name ?? "Unnamed venue" }.joined(separator: " and ")
    }

    /// "Dismissed by Rick M. · Two floors · No longer look alike".
    public var detail: String {
        var parts = ["Dismissed by \(dismissedBy?.name ?? "an admin")"]
        if let note, !note.isEmpty { parts.append(note) }
        parts.append(currentReasons.isEmpty ? "No longer look alike" : "Still: " + currentReasons.map(\.title).joined(separator: ", "))
        return parts.joined(separator: " · ")
    }
}

/// The GraphQL for reviewing an audience's proposed changes and headshots, and undoing "Not a duplicate", from a staff
/// app (Focus), as the web console's Proposed changes and Venues pages do: shared so no app writes its own, and the
/// same on Android word for word. They run on the staff endpoint (`# endpoint: staff`), which this SDK doesn't call:
/// StaffKit's session sends them. The API decides who may: the queue needs `audience:moderate:*`, undoing a dismissal
/// `venues:write:*`.
public enum ProposedChanges {
    /// 24 rows keep the query within a moderator's complexity budget, as on the console; deciding brings in the rest.
    public static let pageSize = 24

    public static let queueQuery = """
        # endpoint: staff
        query FocusProposedChanges($open: Boolean!, $first: Int!) { submissions(open: $open, first: $first) { \
        totalCount nodes { id kind status risk createdAt decidedAt proposed current choices \
        choiceProfiles { username status name pictureUrl biography followersCount postsCount imageUrls error } \
        body evidence submitterRole reporterCount disputeCount person { id name } venue { id name } \
        event { id name } locale { id name } research { summary recommendation } \
        decisions { action reason createdAt reviewer { id name } } } } }
        """

    /// How many are waiting, for a badge.
    public static let openCountQuery = """
        # endpoint: staff
        query FocusProposedChangesCount { submissions(open: true, first: 1) { totalCount } }
        """

    public static let decideMutation = """
        # endpoint: staff
        mutation FocusDecideProposedChange($id: ID!, $action: SubmissionDecisionAction!, $proposed: JSON, $reason: String) { \
        decideSubmission(input: { id: $id, action: $action, proposed: $proposed, reason: $reason }) { \
        submission { id status decidedAt } } }
        """

    public static let headshotsQuery = """
        # endpoint: staff
        query FocusHeadshotsToReview { headshotsToReview(limit: 24) { id url origin sourceUrl person { id name } } }
        """

    public static let approveHeadshotMutation = """
        # endpoint: staff
        mutation FocusApproveHeadshot($id: ID!) { setPersonHeadshotApproval(input: { id: $id, approved: true }) { person { id } } }
        """

    public static let removeHeadshotMutation = """
        # endpoint: staff
        mutation FocusRemoveHeadshot($id: ID!) { removePersonHeadshot(input: { id: $id }) { person { id } } }
        """

    public static let dismissedDuplicatesQuery = """
        # endpoint: staff
        query FocusDismissedVenueDuplicates { venues { dismissedDuplicates { id active note dismissedAt \
        dismissedBy { id name } reasons currentReasons venues { id name } } } }
        """

    public static let restoreDuplicateMutation = """
        # endpoint: staff
        mutation FocusRestoreVenueDuplicate($id: ID!) { restoreVenueDuplicate(input: { id: $id }) { clientMutationId } }
        """

    /// The variables for ``queueQuery``: open ones (first in line first), or decided ones (newest first).
    public static func queueVariables(open: Bool, first: Int = pageSize) -> [String: GraphQLValue] {
        ["open": .bool(open), "first": .int(first)]
    }

    /// The variables for ``decideMutation`` approving it as proposed.
    public static func approveVariables(_ change: ProposedChange) -> [String: GraphQLValue] {
        decideVariables(id: change.id, action: .approve)
    }

    /// The variables for ``decideMutation`` approving a social profile with `handle`: as proposed when it is the
    /// proposed one, else EDIT_APPROVE with {provider, handle}. A pasted profile link or "@" is trimmed to the handle.
    public static func approveVariables(_ change: ProposedChange, handle: String) -> [String: GraphQLValue] {
        let handle = Self.handle(from: handle)
        if handle == change.proposedHandle { return approveVariables(change) }
        return decideVariables(id: change.id, action: .editApprove,
                               proposed: .object(["provider": .string(change.provider ?? ""), "handle": .string(handle)]))
    }

    /// The variables for ``decideMutation`` rejecting it; `reason` is required, and whoever suggested it sees it.
    public static func rejectVariables(_ change: ProposedChange, reason: String) -> [String: GraphQLValue] {
        decideVariables(id: change.id, action: .reject, reason: reason.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// The variables for ``decideMutation`` asking the venue's staff to confirm it.
    public static func askVenueVariables(_ change: ProposedChange) -> [String: GraphQLValue] {
        decideVariables(id: change.id, action: .needsVenue)
    }

    /// The variables for ``decideMutation``.
    public static func decideVariables(id: String, action: ProposedChangeAction, proposed: GraphQLValue? = nil,
                                       reason: String? = nil) -> [String: GraphQLValue] {
        ["id": .string(id), "action": .string(action.rawValue), "proposed": proposed ?? .null,
         "reason": reason.map(GraphQLValue.string) ?? .null]
    }

    /// The variables for the headshot mutations and ``restoreDuplicateMutation``.
    public static func idVariables(_ id: String) -> [String: GraphQLValue] { ["id": .string(id)] }

    /// The reject reason to start from: an import's proposal is usually just not a match.
    public static func suggestedRejectReason(_ change: ProposedChange) -> String {
        change.submitterRole == "system" ? "Not a match" : ""
    }

    /// `@murrayhill`, `instagram.com/murrayhill/` or `https://www.tiktok.com/@murrayhill` → `murrayhill`.
    public static func handle(from text: String) -> String {
        var handle = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if handle.contains("/"), let url = URL(string: handle.contains("://") ? handle : "https://" + handle) {
            handle = url.path.split(separator: "/").first.map(String.init) ?? handle
        }
        while handle.hasPrefix("@") { handle.removeFirst() }
        return handle
    }

    static func kindTitle(_ kind: String) -> String {
        switch kind {
        case "SOCIAL_LINK": "Social profile"
        case "CORRECTION": "Correction"
        case "MISSING_VENUE": "Missing venue"
        case "MISSING_EVENT": "Missing event"
        case "CLOSED": "Reported closed"
        case "TAG_SUGGESTION": "Tag"
        case "LOCAL_RULES_CORRECTION": "Local rules"
        case "TALENT_LINK": "Performer"
        case "TRIBE_SUGGESTION": "Tribe"
        default: "Change"
        }
    }

    static func roleTitle(_ role: String) -> String {
        switch role {
        case "system": "an import"
        case "attendee": "a member"
        case "talent": "talent"
        case "venue_staff": "venue staff"
        case "admin": "an admin"
        default: "someone"
        }
    }

    static func statusTitle(_ status: String) -> String {
        switch status {
        case "SUBMITTED": "Filed"
        case "RESEARCHING": "Researching"
        case "IN_REVIEW": "In review"
        case "NEEDS_VENUE": "Asked the venue"
        case "APPROVED": "Approved"
        case "REJECTED": "Rejected"
        case "MERGED": "Merged"
        default: status.capitalized
        }
    }

    /// "Instagram" for instagram.
    public static func networkTitle(_ provider: String?) -> String? {
        switch provider {
        case "instagram": "Instagram"
        case "facebook": "Facebook"
        case "tiktok": "TikTok"
        case "x": "X"
        case "threads": "Threads"
        case "bluesky": "Bluesky"
        case "youtube": "YouTube"
        case "soundcloud": "SoundCloud"
        case "spotify": "Spotify"
        case "apple_music": "Apple Music"
        case "linktree": "Linktree"
        default: nil
        }
    }

    static func profileURL(provider: String?, handle: String) -> URL? {
        let page: String? = switch provider {
        case "instagram": "https://www.instagram.com/\(handle)/"
        case "tiktok": "https://www.tiktok.com/@\(handle)"
        case "x": "https://x.com/\(handle)"
        case "threads": "https://www.threads.net/@\(handle)"
        case "facebook": "https://www.facebook.com/\(handle)"
        default: nil
        }
        return page.flatMap(URL.init(string:))
    }

    /// ``queueQuery``'s answer; empty for someone who isn't allowed to see it.
    public struct QueueResponse: Decodable, Sendable {
        struct Connection: Decodable, Sendable { let totalCount: Int; let nodes: [ProposedChange?]? }
        let submissions: Connection?
        public var changes: [ProposedChange] { submissions?.nodes?.compactMap { $0 } ?? [] }
        public var totalCount: Int { submissions?.totalCount ?? 0 }
    }

    /// ``headshotsQuery``'s answer.
    public struct HeadshotsResponse: Decodable, Sendable {
        let headshotsToReview: [HeadshotToReview]?
        public var headshots: [HeadshotToReview] { headshotsToReview ?? [] }
    }

    /// ``dismissedDuplicatesQuery``'s answer: the ones still standing first, newest first, as the API sends them.
    public struct DismissedDuplicatesResponse: Decodable, Sendable {
        struct Venues: Decodable, Sendable { let dismissedDuplicates: [VenueDuplicateDismissal]? }
        let venues: Venues?
        public var dismissals: [VenueDuplicateDismissal] { venues?.dismissedDuplicates ?? [] }
        /// The ones not undone, which "Undo" applies to.
        public var active: [VenueDuplicateDismissal] { dismissals.filter(\.active) }
    }
}

/// The words around proposed changes, the same on Android and as the web console's.
public enum ProposedChangesCopy {
    public static let title = "Proposed changes"
    public static let summary = "Changes that need a person before they go live: profiles an import wasn’t sure of, "
        + "and what members suggest. Approve to apply one, or reject it and nothing changes."
    public static let toReview = "To review"
    public static let decided = "Decided"
    public static let approve = "Approve"
    public static let reject = "Reject"
    public static let askVenue = "Ask the venue"
    public static let other = "Other…"
    public static let otherPrompt = "Which handle or profile link is theirs?"
    public static let rejectPrompt = "Why reject it? Whoever suggested it sees this."
    public static let rejectReasonRequired = "Say why it was rejected."
    public static let nothingToReview = "Nothing to review"
    public static let nothingToReviewDetail = "When an import isn’t sure of a change, or a member suggests one, it "
        + "waits here until someone approves it."
    public static let nothingDecided = "Nothing decided yet"
    public static let nothingDecidedDetail = "Changes you approve or reject stay here, with what was decided."
    public static let approved = "Approved, and the listing is updated."
    public static let rejected = "Rejected. Nothing changed."
    public static let askedVenue = "Asked the venue’s staff to confirm it."
    public static let headshots = "Headshots to review"
    public static let headshotsDetail = "Picked from each performer’s own Instagram posts and cropped, or found by a "
        + "worker. Approve the ones that are really them and look right."
    public static let removeHeadshot = "Remove"
    public static let headshotRemoved = "Removed."
    public static let notDuplicates = "Not duplicates"
    public static let notDuplicatesDetail = "Pairs someone said are different places. Undo one to see it suggested again."
    public static let undo = "Undo"

    /// "Use @murrayhill".
    public static func use(_ handle: String) -> String { "Use @\(handle)" }

    /// After approving a social profile: "@murrayhill is now Murray Hill’s Instagram."
    public static func handleApproved(_ change: ProposedChange, handle: String) -> String {
        let network = ProposedChanges.networkTitle(change.provider) ?? "profile"
        return "@\(ProposedChanges.handle(from: handle)) is now \(change.subject?.name ?? "their")’s \(network)."
    }

    /// After approving a headshot.
    public static func headshotApproved(_ name: String?) -> String {
        "Approved for \(name ?? "them"). Its cut-out is on the way."
    }

    /// "Showing 24 of 31. Decide these to see the rest."
    public static func showing(_ shown: Int, of total: Int, open: Bool) -> String {
        "Showing \(shown) of \(total)." + (open ? " Decide these to see the rest." : "")
    }

    /// "Now: @old · Found: @a, @b".
    public static func socialLine(_ change: ProposedChange) -> String {
        let now = change.currentHandle.map { "@\($0)" } ?? "none"
        return "Now: \(now) · Found: " + change.choices.map { "@\($0)" }.joined(separator: ", ")
    }

    /// "2 say it’s wrong."
    public static func disputes(_ count: Int) -> String { "\(count) say it’s wrong." }
}

fileprivate extension GraphQLValue {
    /// An object's member; nil for anything else.
    func member(_ key: String) -> GraphQLValue? {
        if case .object(let fields) = self { return fields[key] }
        return nil
    }

    /// A string's text; nil for anything else.
    var textValue: String? {
        if case .string(let text) = self { return text }
        return nil
    }
}
