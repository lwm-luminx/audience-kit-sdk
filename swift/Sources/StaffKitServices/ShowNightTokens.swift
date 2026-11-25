//
//  ShowNightTokens.swift
//  Backstage's show-night Live Activity (the performer's next appearance across the Lock Screen and in the Dynamic
//  Island), started, updated and ended by the API: the app hands over its push-to-start token, so the API starts the
//  activity a few hours before their next appearance even when Backstage hasn't been opened that day, and each
//  activity's own token, so the API updates it when the event moves and ends it after the set.
//

import AudienceKit
import Foundation
import StaffKitCore

/// Which show-night token: the app's push-to-start token, or one running activity's own.
public enum ShowNightTokenKind: String, Sendable {
    case start = "START"
    case activity = "ACTIVITY"
}

extension TalentManagementClient {
    /// Hands the API a show-night token. `personID` (start) is the listing chosen in Backstage, nil for every one of
    /// theirs; `eventID` (activity) is the event the activity shows.
    public func registerShowNightToken(kind: ShowNightTokenKind, pushToken: String, appID: String, sandbox: Bool,
                                       personID: String? = nil, eventID: String? = nil) async throws {
        struct Payload: Decodable, Sendable { let registered: Bool }
        struct Response: Decodable, Sendable { let registerShowNightToken: Payload }
        var variables: [String: GraphQLValue] = ["kind": .string(kind.rawValue), "pushToken": .string(pushToken),
                                                 "appId": .string(appID), "sandbox": .bool(sandbox)]
        if let personID { variables["personId"] = .string(personID) }
        if let eventID { variables["eventId"] = .string(eventID) }
        _ = try await showNightGraphQL("""
            mutation ShowNightTokenRegister($kind: ShowNightTokenKind!, $pushToken: String!, $appId: String!, $sandbox: Boolean!, $personId: ID, $eventId: ID) {
              registerShowNightToken(input: { kind: $kind, pushToken: $pushToken, appId: $appId, sandbox: $sandbox, personId: $personId, eventId: $eventId }) { registered }
            }
            """, variables: variables, as: Response.self)
    }

    /// Tells the API to stop pushing a show-night token: the activity ended or was swiped away (it isn't started
    /// again for that event), or the app is signing out (its push-to-start token).
    public func endShowNightToken(pushToken: String) async throws {
        struct Payload: Decodable, Sendable { let ended: Bool }
        struct Response: Decodable, Sendable { let endShowNightToken: Payload }
        _ = try await showNightGraphQL("""
            mutation ShowNightTokenEnd($pushToken: String!) { endShowNightToken(input: { pushToken: $pushToken }) { ended } }
            """, variables: ["pushToken": .string(pushToken)], as: Response.self)
    }

    /// The chosen audience's staff endpoint, or the audience-less one while a performer works on their own listings
    /// with no audience chosen.
    private func showNightGraphQL<Response: Decodable & Sendable>(_ query: String, variables: [String: GraphQLValue],
                                                                 as type: Response.Type) async throws -> Response {
        do {
            return try await session.graphQL(query, variables: variables, as: type)
        } catch AudienceKitError.missingConfiguration {
            return try await session.ownListingsGraphQL("# endpoint: audienceless\n" + query, variables: variables, as: type)
        }
    }
}
