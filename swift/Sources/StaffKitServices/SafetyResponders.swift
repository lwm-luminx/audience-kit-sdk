import Foundation
import AudienceCore
import StaffKitCore

/// A safety responder (api doc/SAFETY_ALERTS.md, "Responders"): a social worker or moderator an audience's admins
/// named to back up venue staff on safety alerts, for the whole community or for some of its locales. Arbiter shows
/// them the alerts they cover and lets them act as venue staff would.
public struct SafetyResponder: Decodable, Sendable, Hashable {
    public struct LocaleRef: Decodable, Sendable, Hashable, Identifiable {
        public let id: String
        public let name: String
    }

    /// SOCIAL_WORKER or MODERATOR.
    public let kind: String
    /// ALL, ESCALATED or NONE: when they are pushed.
    public let hears: String
    public let onDuty: Bool
    /// Whether they cover every venue in the community.
    public let everywhere: Bool
    /// The locales they cover (with those within them); empty when `everywhere`.
    public let locales: [LocaleRef]

    public init(kind: String, hears: String, onDuty: Bool, everywhere: Bool, locales: [LocaleRef] = []) {
        self.kind = kind; self.hears = hears; self.onDuty = onDuty; self.everywhere = everywhere; self.locales = locales
    }

    /// "Every venue", or the locales' names ("Salt Lake, Provo").
    public var coverage: String {
        everywhere || locales.isEmpty ? "Every venue" : locales.map(\.name).joined(separator: ", ")
    }

    /// The choices for when they're pushed, in the order Arbiter offers them.
    public static let hearsChoices: [(value: String, title: String, detail: String)] = [
        ("ESCALATED", "When staff need backup", "Nobody on shift picked it up within two minutes, or the guest sent it again."),
        ("ALL", "Every alert", "As soon as a guest sends one, alongside the venue's staff."),
        ("NONE", "Never", "Look in Arbiter when you choose."),
    ]
}

/// What Arbiter reads and does for a safety responder: the alerts at the venues they cover (admins: every venue),
/// their own responder settings, and the same actions venue staff have, plus sharing a community resource.
public struct SafetyResponderClient: Sendable {
    public let session: AudienceManagementSession
    public init(session: AudienceManagementSession) { self.session = session }

    static let resourceFields = "id title phone textNumber address url intakeNote sensitive"
    /// What a responder sees: everything venue staff see but who sent it, plus the venue and shared resources.
    static let alertFields = """
        id state place concerns description summary seen seenByMe acknowledgedByName acknowledgedByResponder \
        acknowledgedAt escalatedAt remindedAt closedAt outcome staffNote supportSharedAt supportNote createdAt \
        venue { id name locale { id name } } event { id name } \
        messages { id body fromStaff senderName createdAt resource { \(resourceFields) } }
        """
    static let responderFields = "kind hears onDuty everywhere locales { id name }"

    /// The caller as a safety responder here; nil when they aren't one (an admin still sees every venue's alerts).
    public func responder() async throws -> SafetyResponder? {
        struct Response: Decodable, Sendable { let safetyResponder: SafetyResponder? }
        return try await session.graphQL("query ArbiterSafetyResponder { safetyResponder { \(Self.responderFields) } }",
                                         as: Response.self).safetyResponder
    }

    /// The alerts the caller covers, newest first: open or picked up, and those closed in the last 12 hours.
    /// `localeID` narrows it to one locale and those within it.
    public func alerts(localeID: String? = nil) async throws -> [StaffSafetyAlert] {
        struct Response: Decodable, Sendable { let responderSafetyAlerts: GraphQLNodes<StaffSafetyAlert> }
        var variables: [String: GraphQLValue] = [:]
        if let localeID { variables["localeId"] = .string(localeID) }
        return try await session.graphQL("query ArbiterSafetyAlerts($localeId: ID) { responderSafetyAlerts(localeId: $localeId, first: 100) { nodes { \(Self.alertFields) } } }",
                                         variables: variables, as: Response.self).responderSafetyAlerts.nodes
    }

    /// On or off duty, and when they're pushed (nil keeps it).
    @discardableResult
    public func setDuty(onDuty: Bool, hears: String? = nil) async throws -> SafetyResponder? {
        struct Payload: Decodable, Sendable { let safetyResponder: SafetyResponder? }
        struct Response: Decodable, Sendable { let setSafetyResponderDuty: Payload? }
        var input: [String: GraphQLValue] = ["onDuty": .bool(onDuty)]
        if let hears { input["hears"] = .string(hears) }
        return try await session.graphQL("mutation ArbiterSetSafetyResponderDuty($input: SafetyResponderDutySetInput!) { setSafetyResponderDuty(input: $input) { safetyResponder { \(Self.responderFields) } } }",
                                         variables: ["input": .object(input)], as: Response.self).setSafetyResponderDuty?.safetyResponder
    }

    /// The community resources in a locale (and the locales above and within it), to share with a guest.
    public func resources(localeID: String) async throws -> [StaffSafetyAlert.SharedResource] {
        struct Response: Decodable, Sendable { let communityResources: [StaffSafetyAlert.SharedResource] }
        return try await session.graphQL("query ArbiterCommunityResources($localeId: ID!) { communityResources(localeId: $localeId) { \(Self.resourceFields) } }",
                                         variables: ["localeId": .string(localeID)], as: Response.self).communityResources
    }

    /// Stores this device's APNs token on the session, so the responder's alerts push Arbiter. `appID` is the app's
    /// bundle ID, which the push is addressed to.
    public func registerDevice(token: String, appID: String, sandbox: Bool) async throws {
        _ = try await session.graphQL(RoomsClient.registerDeviceMutation, variables: ["input": .object([
            "notificationToken": .string(token), "appId": .string(appID), "sandbox": .bool(sandbox)
        ])], as: GraphQLValue.self)
    }

    @discardableResult
    public func see(id: String) async throws -> StaffSafetyAlert {
        try await mutation("seeSafetyAlert", "mutation ArbiterSeeSafetyAlert($input: SafetyAlertSeeInput!) { seeSafetyAlert(input: $input) { safetyAlert { \(Self.alertFields) } } }", ["id": .string(id)])
    }

    /// "I'm on it": the guest is told `name` (or the account's first name) is here to help in the thread.
    @discardableResult
    public func acknowledge(id: String, name: String? = nil) async throws -> StaffSafetyAlert {
        var input: [String: GraphQLValue] = ["id": .string(id)]
        if let name, !name.isEmpty { input["staffName"] = .string(name) }
        return try await mutation("acknowledgeSafetyAlert", "mutation ArbiterAcknowledgeSafetyAlert($input: SafetyAlertAcknowledgeInput!) { acknowledgeSafetyAlert(input: $input) { safetyAlert { \(Self.alertFields) } } }", input)
    }

    @discardableResult
    public func sendMessage(id: String, body: String) async throws -> StaffSafetyAlert {
        try await mutation("sendSafetyAlertMessage", "mutation ArbiterSendSafetyAlertMessage($input: SafetyAlertMessageSendInput!) { sendSafetyAlertMessage(input: $input) { safetyAlert { \(Self.alertFields) } } }", ["id": .string(id), "body": .string(body)])
    }

    /// Shares "Need support?" (crisis and support lines), with a note if you like.
    @discardableResult
    public func shareSupport(id: String, note: String?) async throws -> StaffSafetyAlert {
        var input: [String: GraphQLValue] = ["id": .string(id)]
        if let note, !note.isEmpty { input["note"] = .string(note) }
        return try await mutation("shareSafetyAlertSupport", "mutation ArbiterShareSafetyAlertSupport($input: SafetyAlertSupportShareInput!) { shareSafetyAlertSupport(input: $input) { safetyAlert { \(Self.alertFields) } } }", input)
    }

    /// Shares one community resource in the thread (and its chat room), with a line before it if you like.
    @discardableResult
    public func shareResource(id: String, resourceID: String, note: String?) async throws -> StaffSafetyAlert {
        var input: [String: GraphQLValue] = ["id": .string(id), "resourceId": .string(resourceID)]
        if let note, !note.isEmpty { input["note"] = .string(note) }
        return try await mutation("shareSafetyAlertResource", "mutation ArbiterShareSafetyAlertResource($input: SafetyAlertResourceShareInput!) { shareSafetyAlertResource(input: $input) { safetyAlert { \(Self.alertFields) } } }", input)
    }

    @discardableResult
    public func close(id: String, outcome: String, note: String?) async throws -> StaffSafetyAlert {
        var input: [String: GraphQLValue] = ["id": .string(id), "outcome": .string(outcome)]
        if let note, !note.isEmpty { input["note"] = .string(note) }
        return try await mutation("closeSafetyAlert", "mutation ArbiterCloseSafetyAlert($input: SafetyAlertCloseInput!) { closeSafetyAlert(input: $input) { safetyAlert { \(Self.alertFields) } } }", input)
    }

    private struct Payload: Decodable, Sendable { let safetyAlert: StaffSafetyAlert? }

    /// Runs one of the alert mutations, each named `name` and answering `{ safetyAlert }`.
    private func mutation(_ name: String, _ document: String, _ input: [String: GraphQLValue]) async throws -> StaffSafetyAlert {
        let response = try await session.graphQL(document, variables: ["input": .object(input)], as: [String: Payload?].self)
        guard let alert = response[name]??.safetyAlert else { throw SafetyAlertError.missing }
        return alert
    }
}

extension SafetyAlertPush {
    /// Whether the push was for a safety responder (`data.responder`), which Arbiter opens in its Need help page.
    public static func isForResponder(_ userInfo: [AnyHashable: Any]) -> Bool {
        (userInfo["responder"] as? String) == "true" || (userInfo["responder"] as? Bool) == true
    }
}
