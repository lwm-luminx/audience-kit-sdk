import Foundation
import AudienceCore
import StaffKitCore

/// A request to be a safety responder (the API's doc/SAFETY_ALERTS.md, "Applying"), with the accreditation the
/// applicant holds. Only the audience's admins and the applicant ever see one; `email` and `reviewNote` are the
/// admins' alone (null for the applicant).
public struct SafetyResponderApplication: Decodable, Sendable, Hashable, Identifiable {
    public let id: String
    public let audienceId: String
    public let audienceName: String
    public let name: String
    public let email: String?
    /// MODERATOR or SOCIAL_WORKER.
    public let kind: String
    /// One of ``credentials``' values.
    public let credential: String
    public let credentialOther: String?
    public let licenseNumber: String?
    public let issuedBy: String?
    public let note: String?
    /// PENDING, APPROVED, DECLINED or WITHDRAWN.
    public let status: String
    public let reviewNote: String?
    public let createdAt: String
    public let reviewedAt: String?

    public var isPending: Bool { status == "PENDING" }

    /// The accreditation in words: "LCSW", or what they named for OTHER.
    public var credentialTitle: String {
        credential == "OTHER" ? (credentialOther ?? "Other") : (Self.credentials.first { $0.value == credential }?.title ?? credential)
    }

    /// Where it stands, in a few words.
    public var statusTitle: String {
        switch status {
        case "PENDING": "Waiting for an admin"
        case "APPROVED": "Approved"
        case "DECLINED": "Declined"
        case "WITHDRAWN": "Withdrawn"
        default: status.capitalized
        }
    }

    /// The accreditations Arbiter offers, in order: value, title.
    public static let credentials: [(value: String, title: String)] = [
        ("LCSW", "LCSW (licensed clinical social worker)"),
        ("LMSW", "LMSW or MSW"),
        ("LPC", "LPC or other licensed counselor"),
        ("PEER_SUPPORT", "Certified peer support specialist"),
        ("CRISIS_COUNSELOR", "Crisis counselor"),
        ("MODERATOR_TRAINING", "Moderator training"),
        ("OTHER", "Something else"),
    ]
}

/// A community the signed-in person belongs to, to apply in (`me { responderCommunities }`).
public struct ResponderCommunity: Decodable, Sendable, Hashable, Identifiable {
    public let audienceId: String
    public let name: String
    /// Already a safety responder there.
    public let responder: Bool
    /// An application there is waiting for an admin.
    public let pending: Bool
    public var id: String { audienceId }
}

/// What someone applying fills in.
public struct SafetyResponderApplicationInput: Sendable, Hashable {
    public var audienceID: String
    public var kind: String
    public var credential: String
    public var credentialOther: String?
    public var licenseNumber: String?
    public var issuedBy: String?
    public var note: String?

    public init(audienceID: String, kind: String = "SOCIAL_WORKER", credential: String = "LCSW",
                credentialOther: String? = nil, licenseNumber: String? = nil, issuedBy: String? = nil, note: String? = nil) {
        self.audienceID = audienceID; self.kind = kind; self.credential = credential
        self.credentialOther = credentialOther; self.licenseNumber = licenseNumber; self.issuedBy = issuedBy; self.note = note
    }
}

/// Applying to be a safety responder, from Arbiter signed in on the platform with no audience open: the audience-less
/// staffql (`/v1/staffql`). The admins' side is ``SafetyResponderClient/applications(status:)`` on an audience.
public struct SafetyResponderApplyClient: Sendable {
    public let session: AudienceManagementSession
    public init(session: AudienceManagementSession) { self.session = session }

    static let applicationFields = "id audienceId audienceName name email kind credential credentialOther licenseNumber issuedBy note status reviewNote createdAt reviewedAt"

    /// Whether this sign-in can apply now: signed in on the platform with no audience chosen.
    public var canApply: Bool { get async { await session.canUseOwnListings } }

    /// The communities they belong to, and their applications, newest first.
    public func overview() async throws -> (communities: [ResponderCommunity], applications: [SafetyResponderApplication]) {
        struct Me: Decodable, Sendable { let responderCommunities: [ResponderCommunity]; let safetyResponderApplications: [SafetyResponderApplication] }
        struct Response: Decodable, Sendable { let me: Me }
        let me = try await session.ownListingsGraphQL("# endpoint: audienceless\nquery ArbiterResponderApplications { me { responderCommunities { audienceId name responder pending } safetyResponderApplications { \(Self.applicationFields) } } }",
                                                      as: Response.self).me
        return (me.responderCommunities, me.safetyResponderApplications)
    }

    @discardableResult
    public func apply(_ input: SafetyResponderApplicationInput) async throws -> SafetyResponderApplication {
        struct Payload: Decodable, Sendable { let application: SafetyResponderApplication }
        struct Response: Decodable, Sendable { let applyToBeSafetyResponder: Payload }
        var fields: [String: GraphQLValue] = ["audienceId": .string(input.audienceID), "kind": .string(input.kind),
                                              "credential": .string(input.credential)]
        for (key, value) in [("credentialOther", input.credentialOther), ("licenseNumber", input.licenseNumber),
                             ("issuedBy", input.issuedBy), ("note", input.note)] {
            if let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty { fields[key] = .string(value) }
        }
        return try await session.ownListingsGraphQL("# endpoint: audienceless\nmutation ArbiterApplyToBeSafetyResponder($input: SafetyResponderApplyInput!) { applyToBeSafetyResponder(input: $input) { application { \(Self.applicationFields) } } }",
                                                    variables: ["input": .object(fields)], as: Response.self).applyToBeSafetyResponder.application
    }

    @discardableResult
    public func withdraw(id: String) async throws -> SafetyResponderApplication {
        struct Payload: Decodable, Sendable { let application: SafetyResponderApplication }
        struct Response: Decodable, Sendable { let withdrawSafetyResponderApplication: Payload }
        return try await session.ownListingsGraphQL("# endpoint: audienceless\nmutation ArbiterWithdrawSafetyResponderApplication($input: SafetyResponderApplicationWithdrawInput!) { withdrawSafetyResponderApplication(input: $input) { application { \(Self.applicationFields) } } }",
                                                    variables: ["input": .object(["id": .string(id)])], as: Response.self).withdrawSafetyResponderApplication.application
    }
}

/// A locale an admin can pick for a responder to cover (a state, a city), with every locale within it.
public struct ResponderLocale: Decodable, Sendable, Hashable, Identifiable {
    public let id: String
    public let name: String?
    /// The API's LocaleKind, e.g. STATE or CITY.
    public let kind: String
    public var title: String { name ?? kind.capitalized }
}

extension SafetyResponderClient {
    /// The audience's top-level locales, or those directly within `parentID`, by name: for choosing what an approved
    /// responder covers.
    public func locales(parentID: String? = nil) async throws -> [ResponderLocale] {
        struct Response: Decodable, Sendable { let locales: [ResponderLocale] }
        let locales: [ResponderLocale]
        if let parentID {
            locales = try await session.graphQL("query ArbiterResponderLocalesWithin($parentId: ID) { locales(parentId: $parentId) { id name kind } }",
                                                variables: ["parentId": .string(parentID)], as: Response.self).locales
        } else {
            locales = try await session.graphQL("query ArbiterResponderLocales { locales(roots: true) { id name kind } }",
                                                as: Response.self).locales
        }
        return locales.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    /// The audience's applications to be a safety responder, newest first: the pending ones by default. Admins only
    /// (empty for anyone else).
    public func applications(status: String = "PENDING") async throws -> [SafetyResponderApplication] {
        struct Response: Decodable, Sendable { let safetyResponderApplications: [SafetyResponderApplication] }
        return try await session.graphQL("query ArbiterSafetyResponderApplications($status: SafetyResponderApplicationStatus) { safetyResponderApplications(status: $status) { \(SafetyResponderApplyClient.applicationFields) } }",
                                         variables: ["status": .string(status)], as: Response.self).safetyResponderApplications
    }

    /// Approves (making them a responder for `localeIDs`, every venue when empty) or declines an application.
    @discardableResult
    public func review(id: String, approve: Bool, localeIDs: [String] = [], note: String? = nil) async throws -> SafetyResponderApplication {
        struct Payload: Decodable, Sendable { let application: SafetyResponderApplication }
        struct Response: Decodable, Sendable { let reviewSafetyResponderApplication: Payload }
        var input: [String: GraphQLValue] = ["id": .string(id), "approve": .bool(approve)]
        if approve { input["localeIds"] = .array(localeIDs.map { .string($0) }) }
        if let note = note?.trimmingCharacters(in: .whitespacesAndNewlines), !note.isEmpty { input["note"] = .string(note) }
        return try await session.graphQL("mutation ArbiterReviewSafetyResponderApplication($input: SafetyResponderApplicationReviewInput!) { reviewSafetyResponderApplication(input: $input) { application { \(SafetyResponderApplyClient.applicationFields) } } }",
                                         variables: ["input": .object(input)], as: Response.self).reviewSafetyResponderApplication.application
    }
}
