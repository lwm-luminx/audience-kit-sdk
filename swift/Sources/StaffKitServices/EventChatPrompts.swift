import Foundation
import AudienceCore
import StaffKitCore

/// How an event's chat room gets people talking (`Event.chat`, its staff only): whether and when the room shows its
/// prompts, the prompts in the order they show, and the starter sets staff can begin from. The room is its venue's
/// while the event is on. Change it with ``EventChatPromptsClient/save(eventID:draft:)``.
public struct EventChatPrompts: Decodable, Sendable, Hashable {
    /// Whether the room shows its prompts.
    public let promptsEnabled: Bool
    /// How often the pinned prompt changes, from when the event starts; nil when it doesn't rotate.
    public let rotateMinutes: Int?
    /// How long the room is quiet before a prompt drops in as a card (at most one every 30 minutes); nil for never.
    public let idleMinutes: Int?
    /// At most this many prompts a night, pinned and quiet-room together.
    public let nightlyCap: Int
    /// Whether prompts wait while an act is on stage.
    public let pauseDuringActs: Bool
    /// When the next prompt rotates in, if one will.
    public let nextPromptAt: String?
    /// Its prompts, in the order they show: the ones shown tonight first.
    public let prompts: [EventChatPrompt]
    /// Hand-written lists to start from.
    public let starterSets: [EventChatStarterSet]

    public init(promptsEnabled: Bool = false, rotateMinutes: Int? = 45, idleMinutes: Int? = 10, nightlyCap: Int = 6,
                pauseDuringActs: Bool = true, nextPromptAt: String? = nil, prompts: [EventChatPrompt] = [],
                starterSets: [EventChatStarterSet] = []) {
        self.promptsEnabled = promptsEnabled; self.rotateMinutes = rotateMinutes; self.idleMinutes = idleMinutes
        self.nightlyCap = nightlyCap; self.pauseDuringActs = pauseDuringActs; self.nextPromptAt = nextPromptAt
        self.prompts = prompts; self.starterSets = starterSets
    }

    private enum CodingKeys: String, CodingKey {
        case promptsEnabled, rotateMinutes, idleMinutes, nightlyCap, pauseDuringActs, nextPromptAt, prompts, starterSets
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        promptsEnabled = try c.decodeIfPresent(Bool.self, forKey: .promptsEnabled) ?? false
        rotateMinutes = try c.decodeIfPresent(Int.self, forKey: .rotateMinutes)
        idleMinutes = try c.decodeIfPresent(Int.self, forKey: .idleMinutes)
        nightlyCap = try c.decodeIfPresent(Int.self, forKey: .nightlyCap) ?? 6
        pauseDuringActs = try c.decodeIfPresent(Bool.self, forKey: .pauseDuringActs) ?? true
        nextPromptAt = try c.decodeIfPresent(String.self, forKey: .nextPromptAt)
        prompts = (try c.decodeIfPresent([EventChatPrompt].self, forKey: .prompts) ?? []).sorted { $0.position < $1.position }
        starterSets = try c.decodeIfPresent([EventChatStarterSet].self, forKey: .starterSets) ?? []
    }

    /// The prompt pinned under the room's title now: the newest shown as PINNED, unless it was taken down.
    public var livePrompt: EventChatPrompt? {
        guard let newest = prompts.filter({ $0.isShown && $0.shownAs == "PINNED" })
            .max(by: { ($0.shownAt ?? "") < ($1.shownAt ?? "") }), !newest.takenDown else { return nil }
        return newest
    }

    /// The next prompt to go up, if any are left.
    public var nextPrompt: EventChatPrompt? { prompts.first { !$0.isShown } }
}

/// One of an event's chat prompts (`ChatPrompt`).
public struct EventChatPrompt: Decodable, Sendable, Hashable, Identifiable {
    public let id: String
    /// CONVERSATION or TRIVIA; a kind added later decodes as itself.
    public let kind: String
    /// The question.
    public let text: String
    /// A trivia question's answer.
    public let answer: String?
    /// Its place in the night, from 0.
    public let position: Int
    /// When it went up, if it has. Shown prompts stay as they were whatever a save says.
    public let shownAt: String?
    /// PINNED or CARD, once it has gone up.
    public let shownAs: String?
    /// When a trivia question's answer shows for everyone.
    public let revealAt: String?
    /// How many messages in the room answer it.
    public let answerCount: Int
    /// Whether it went up and was taken out of the room since (``EventChatPromptsClient/remove(promptID:)``, or a
    /// moderator removing its card).
    public let takenDown: Bool

    public init(id: String, kind: String = "CONVERSATION", text: String, answer: String? = nil, position: Int = 0,
                shownAt: String? = nil, shownAs: String? = nil, revealAt: String? = nil, answerCount: Int = 0,
                takenDown: Bool = false) {
        self.id = id; self.kind = kind; self.text = text; self.answer = answer; self.position = position
        self.shownAt = shownAt; self.shownAs = shownAs; self.revealAt = revealAt; self.answerCount = answerCount
        self.takenDown = takenDown
    }

    private enum CodingKeys: String, CodingKey { case id, kind, text, answer, position, shownAt, shownAs, revealAt, answerCount, takenDown }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        kind = try c.decodeIfPresent(String.self, forKey: .kind) ?? "CONVERSATION"
        text = try c.decode(String.self, forKey: .text)
        answer = try c.decodeIfPresent(String.self, forKey: .answer)
        position = try c.decodeIfPresent(Int.self, forKey: .position) ?? 0
        shownAt = try c.decodeIfPresent(String.self, forKey: .shownAt)
        shownAs = try c.decodeIfPresent(String.self, forKey: .shownAs)
        revealAt = try c.decodeIfPresent(String.self, forKey: .revealAt)
        answerCount = try c.decodeIfPresent(Int.self, forKey: .answerCount) ?? 0
        takenDown = try c.decodeIfPresent(Bool.self, forKey: .takenDown) ?? false
    }

    public var isTrivia: Bool { kind == "TRIVIA" }
    /// Whether it has gone up tonight; shown prompts can't be edited, moved or removed.
    public var isShown: Bool { shownAt != nil }
}

/// A hand-written list of prompts to start an event from (`ChatPromptStarterSet`), e.g. "Viewing party".
public struct EventChatStarterSet: Decodable, Sendable, Hashable, Identifiable {
    /// One of its prompts, unsaved.
    public struct Prompt: Decodable, Sendable, Hashable {
        public let kind: String
        public let text: String
        public let answer: String?
        public init(kind: String = "CONVERSATION", text: String, answer: String? = nil) {
            self.kind = kind; self.text = text; self.answer = answer
        }
    }
    /// Its key, for `setEventChatPrompts(starterSet:)`.
    public let key: String
    /// What it is for ("Viewing party").
    public let name: String
    public let prompts: [Prompt]
    public var id: String { key }

    public init(key: String, name: String, prompts: [Prompt]) { self.key = key; self.name = name; self.prompts = prompts }
}

/// An event's chat prompt settings being edited: the settings, and the list with the prompts already shown tonight
/// kept apart, since a save can't change them. Turn it into `setEventChatPrompts`' input with ``input(eventID:)``.
public struct EventChatPromptsDraft: Sendable, Hashable {
    /// One prompt still to show, as edited: an existing one (`id`) or a new one.
    public struct Item: Sendable, Hashable, Identifiable {
        /// Stable across edits, for lists; the prompt's ID when it has one.
        public let id: String
        /// The saved prompt's ID; nil for a new one.
        public let promptID: String?
        public var kind: String
        public var text: String
        /// A trivia question's answer; ignored for a conversation prompt.
        public var answer: String

        public init(promptID: String? = nil, kind: String = "CONVERSATION", text: String = "", answer: String = "") {
            self.id = promptID ?? "new-\(UUID().uuidString)"
            self.promptID = promptID; self.kind = kind; self.text = text; self.answer = answer
        }

        public var isTrivia: Bool { kind == "TRIVIA" }
        public var trimmedText: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }
        public var trimmedAnswer: String { answer.trimmingCharacters(in: .whitespacesAndNewlines) }
        /// Has a question within 200 characters, and a trivia question has an answer within 120.
        public var isValid: Bool {
            !trimmedText.isEmpty && trimmedText.count <= EventChatPromptsDraft.textLimit
                && (!isTrivia || (!trimmedAnswer.isEmpty && trimmedAnswer.count <= EventChatPromptsDraft.answerLimit))
        }
    }

    /// The API's limits: a question's and an answer's length, prompts an event holds, and each setting's range.
    public static let textLimit = 200
    public static let answerLimit = 120
    public static let maxPrompts = 30
    public static let rotateRange = 15...240
    public static let idleRange = 5...120
    public static let nightlyCapRange = 1...20

    public var promptsEnabled: Bool
    /// nil: don't rotate.
    public var rotateMinutes: Int?
    /// nil: never drop a card into a quiet room.
    public var idleMinutes: Int?
    public var nightlyCap: Int
    public var pauseDuringActs: Bool
    /// Prompts shown tonight, read-only, in the order they went up.
    public let shown: [EventChatPrompt]
    /// Prompts still to show, in order: editable, reorderable, removable.
    public var upcoming: [Item]
    /// What was loaded, to tell whether anything changed.
    private let original: EventChatPrompts

    public init(_ chat: EventChatPrompts) {
        original = chat
        promptsEnabled = chat.promptsEnabled
        rotateMinutes = chat.rotateMinutes
        idleMinutes = chat.idleMinutes
        nightlyCap = chat.nightlyCap
        pauseDuringActs = chat.pauseDuringActs
        shown = chat.prompts.filter(\.isShown)
        upcoming = chat.prompts.filter { !$0.isShown }.map {
            Item(promptID: $0.id, kind: $0.kind, text: $0.text, answer: $0.answer ?? "")
        }
    }

    /// Whether another prompt fits (an event holds at most 30, shown ones included).
    public var canAdd: Bool { shown.count + upcoming.count < Self.maxPrompts }

    /// Adds a blank prompt at the end, and returns its ID for focusing.
    @discardableResult
    public mutating func addPrompt(kind: String = "CONVERSATION") -> String? {
        guard canAdd else { return nil }
        let item = Item(kind: kind)
        upcoming.append(item)
        return item.id
    }

    /// Replaces the prompts still to show with a starter set's, to edit before saving. Shown ones stay.
    public mutating func start(from set: EventChatStarterSet) {
        upcoming = set.prompts.prefix(max(0, Self.maxPrompts - shown.count)).map {
            Item(kind: $0.kind, text: $0.text, answer: $0.answer ?? "")
        }
    }

    public mutating func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        // IndexSet-based reordering, as List's onMove gives it, without SwiftUI's Array extension.
        let moving = source.sorted().map { upcoming[$0] }
        var rest = upcoming.enumerated().filter { !source.contains($0.offset) }.map(\.element)
        let insertAt = destination - source.filter { $0 < destination }.count
        rest.insert(contentsOf: moving, at: min(max(insertAt, 0), rest.count))
        upcoming = rest
    }

    public mutating func remove(atOffsets offsets: IndexSet) {
        upcoming = upcoming.enumerated().filter { !offsets.contains($0.offset) }.map(\.element)
    }

    /// Every prompt is complete and every setting is in the API's range.
    public var isValid: Bool {
        upcoming.allSatisfy(\.isValid) && canHold(upcoming.count)
            && (rotateMinutes.map { Self.rotateRange.contains($0) } ?? true)
            && (idleMinutes.map { Self.idleRange.contains($0) } ?? true)
            && Self.nightlyCapRange.contains(nightlyCap)
    }
    private func canHold(_ count: Int) -> Bool { shown.count + count <= Self.maxPrompts }

    /// Whether anything differs from what was loaded.
    public var hasChanges: Bool { settingsChanged || listChanged }

    private var settingsChanged: Bool {
        promptsEnabled != original.promptsEnabled || rotateMinutes != original.rotateMinutes
            || idleMinutes != original.idleMinutes || nightlyCap != original.nightlyCap
            || pauseDuringActs != original.pauseDuringActs
    }
    private var listChanged: Bool {
        let before = original.prompts.filter { !$0.isShown }.map { Snapshot(id: $0.id, kind: $0.kind, text: $0.text, answer: $0.isTrivia ? ($0.answer ?? "") : "") }
        let after = upcoming.map { Snapshot(id: $0.promptID, kind: $0.kind, text: $0.trimmedText, answer: $0.isTrivia ? $0.trimmedAnswer : "") }
        return before != after
    }
    private struct Snapshot: Equatable { let id: String?; let kind: String; let text: String; let answer: String }

    /// `setEventChatPrompts`' input: every setting (a nil rotation or idle time is sent as null, which turns it off),
    /// and the prompts still to show, in order; existing ones by ID. Shown prompts aren't sent: they stay as they were.
    public func input(eventID: String) -> [String: GraphQLValue] {
        [
            "id": .string(eventID),
            "promptsEnabled": .bool(promptsEnabled),
            "rotateMinutes": rotateMinutes.map(GraphQLValue.int) ?? .null,
            "idleMinutes": idleMinutes.map(GraphQLValue.int) ?? .null,
            "nightlyCap": .int(nightlyCap),
            "pauseDuringActs": .bool(pauseDuringActs),
            "prompts": .array(upcoming.map(\.input)),
        ]
    }
}

extension EventChatPromptsDraft.Item {
    /// `ChatPromptInput`: the ID of an existing prompt, its kind, the trimmed question, and a trivia question's answer.
    var input: GraphQLValue {
        var fields: [String: GraphQLValue] = ["kind": .string(kind), "text": .string(trimmedText)]
        if let promptID { fields["id"] = .string(promptID) }
        if isTrivia, !trimmedAnswer.isEmpty { fields["answer"] = .string(trimmedAnswer) }
        return .object(fields)
    }
}

/// Reads and changes an event's chat prompts (`Event.chat`, `setEventChatPrompts`), for its staff: admins (Focus),
/// and the people who manage its listing. The server checks access on every call.
public struct EventChatPromptsClient: Sendable {
    public let session: AudienceManagementSession
    public init(session: AudienceManagementSession) { self.session = session }

    /// What a read or a save returns of `Event.chat`.
    static let chatFields = """
        promptsEnabled rotateMinutes idleMinutes nightlyCap pauseDuringActs nextPromptAt
        prompts { id kind text answer position shownAt shownAs revealAt answerCount takenDown }
        starterSets { key name prompts { kind text answer } }
        """
    static let readQuery = """
        query StaffEventChatPrompts($id: ID!) { events { event(id: $id) { id chat { \(chatFields) } } } }
        """
    static let saveMutation = """
        mutation StaffSetEventChatPrompts($input: EventChatPromptsSetInput!) {
          setEventChatPrompts(input: $input) { event { id chat { \(chatFields) } } }
        }
        """

    static let showNextMutation = """
        mutation StaffShowNextChatPrompt($input: ChatPromptShowNextInput!) {
          showNextChatPrompt(input: $input) { event { id chat { \(chatFields) } } }
        }
        """
    static let removeMutation = """
        mutation StaffRemoveChatPrompt($id: ID!) {
          removeChatPrompt(input: { id: $id }) { event { id chat { \(chatFields) } } }
        }
        """

    private struct EventChat: Decodable, Sendable { let id: String; let chat: EventChatPrompts? }

    /// The event's chat prompts; nil when the event isn't there or the viewer isn't its staff.
    public func chatPrompts(eventID: String) async throws -> EventChatPrompts? {
        struct Response: Decodable, Sendable {
            struct Events: Decodable, Sendable { let event: EventChat? }
            let events: Events?
        }
        return try await session.graphQL(Self.readQuery, variables: ["id": .string(eventID)], as: Response.self)
            .events?.event?.chat
    }

    /// Saves the settings and the list of prompts still to show, in its order. Returns the event's prompts after it.
    @discardableResult
    public func save(eventID: String, draft: EventChatPromptsDraft) async throws -> EventChatPrompts {
        try await set(draft.input(eventID: eventID))
    }

    /// Replaces the prompts still to show with a starter set's (`EventChatStarterSet.key`) on the server, leaving the
    /// settings as they are. To edit a set before it's saved, use ``EventChatPromptsDraft/start(from:)`` instead.
    @discardableResult
    public func applyStarterSet(eventID: String, key: String) async throws -> EventChatPrompts {
        try await set(["id": .string(eventID), "starterSet": .string(key)])
    }

    /// Turns the room's prompts on or off, leaving everything else as it is.
    @discardableResult
    public func setPromptsEnabled(eventID: String, _ enabled: Bool) async throws -> EventChatPrompts {
        try await set(["id": .string(eventID), "promptsEnabled": .bool(enabled)])
    }

    /// Puts the event's next prompt up in its room now, pinned, without waiting for the rotation (`showNextChatPrompt`).
    /// It goes up past the nightly cap or while an act is on; the event must be on now. Returns the prompts after it.
    @discardableResult
    public func showNext(eventID: String) async throws -> EventChatPrompts {
        try await showNext(["id": .string(eventID)]).chat
    }

    /// Puts the next prompt of the event on at the venue now up in its room (`showNextChatPrompt(venueId:)`), for a
    /// venue's chat that doesn't know which event is on. Returns that event's ID and its prompts after it.
    @discardableResult
    public func showNext(venueID: String) async throws -> (eventID: String, chat: EventChatPrompts) {
        try await showNext(["venueId": .string(venueID)])
    }

    /// Removes a prompt (`removeChatPrompt`): one still to show comes off the list, skipping it; one that's up is
    /// taken out of the room for everyone and stays in the list as ``EventChatPrompt/takenDown``. Returns the prompts
    /// after it.
    @discardableResult
    public func remove(promptID: String) async throws -> EventChatPrompts {
        struct Response: Decodable, Sendable {
            struct Payload: Decodable, Sendable { let event: EventChat }
            let removeChatPrompt: Payload?
        }
        let response = try await session.graphQL(Self.removeMutation, variables: ["id": .string(promptID)], as: Response.self)
        guard let chat = response.removeChatPrompt?.event.chat else {
            throw AudienceKitError.decoding("The event's chat prompts were missing")
        }
        return chat
    }

    private func showNext(_ input: [String: GraphQLValue]) async throws -> (eventID: String, chat: EventChatPrompts) {
        struct Response: Decodable, Sendable {
            struct Payload: Decodable, Sendable { let event: EventChat }
            let showNextChatPrompt: Payload?
        }
        let response = try await session.graphQL(Self.showNextMutation, variables: ["input": .object(input)], as: Response.self)
        guard let event = response.showNextChatPrompt?.event, let chat = event.chat else {
            throw AudienceKitError.decoding("The event's chat prompts were missing")
        }
        return (event.id, chat)
    }

    private func set(_ input: [String: GraphQLValue]) async throws -> EventChatPrompts {
        struct Response: Decodable, Sendable {
            struct Payload: Decodable, Sendable { let event: EventChat }
            let setEventChatPrompts: Payload?
        }
        let response = try await session.graphQL(Self.saveMutation, variables: ["input": .object(input)], as: Response.self)
        guard let chat = response.setEventChatPrompts?.event.chat else {
            throw AudienceKitError.decoding("The event's chat prompts were missing")
        }
        return chat
    }
}
