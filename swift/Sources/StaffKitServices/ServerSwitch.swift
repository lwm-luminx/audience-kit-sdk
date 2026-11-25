import Foundation
import AudienceCore
import StaffKitCore

/// Whether the signed-in person may pick the API server in any install (`me.canSwitchServer`: AudienceKit super
/// admins), remembered for the staff apps and Arbiter on this device (``StaffBeta/remember(canSwitchServer:)``).
public struct ServerSwitchClient: Sendable {
    let session: AudienceManagementSession

    public init(session: AudienceManagementSession) { self.session = session }

    /// Asks and remembers; an API that predates `canSwitchServer` fails only this.
    @discardableResult
    public func refresh() async throws -> Bool {
        struct Response: Decodable, Sendable { struct Me: Decodable, Sendable { let canSwitchServer: Bool }; let me: Me? }
        let allowed = try await session.graphQL("query StaffServerSwitch { me { canSwitchServer } }",
                                                as: Response.self).me?.canSwitchServer ?? false
        StaffBeta.remember(canSwitchServer: allowed)
        return allowed
    }
}
