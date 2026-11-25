import Foundation
import Testing
import AudienceKit
import StaffKitCore
import StaffKitServices

private let manager = makeCredential(token: "manager", audienceID: "hot-mess")
private let device = makeCredential(token: "device", audienceID: "hot-mess", venueDeviceID: "grant-1",
                                    role: "venue_device")

@Test func managerSessionsAreSharedAndDeviceSessionsStayWithTheApp() throws {
    let shared = InMemoryCredentialStore()
    let app = InMemoryCredentialStore()
    let store = StaffCredentialStore(shared: shared, app: app)

    try store.save(manager)
    #expect(try shared.load() == manager)
    #expect(try app.load() == nil)
    #expect(try store.load() == manager)

    try store.save(device)
    #expect(try app.load() == device)
    #expect(try shared.load() == manager, "a door device never signs the manager out of the other apps")
    #expect(try store.load() == device, "this app is the device while its code is redeemed")

    try store.delete()
    #expect(try app.load() == nil)
    #expect(try shared.load() == manager)
    #expect(try store.load() == manager)

    try store.delete()
    #expect(try shared.load() == nil)
}

@Test func managerCredentialFromAnOlderBuildMovesToTheSharedItem() throws {
    let shared = InMemoryCredentialStore()
    let app = InMemoryCredentialStore(credential: manager)
    let store = StaffCredentialStore(shared: shared, app: app)
    #expect(try store.load() == manager)
    #expect(try shared.load() == manager)
    #expect(try app.load() == nil)
}

@Test func aSiblingSignInWinsOverAnOlderBuildsCredential() throws {
    let newer = makeCredential(token: "newer")
    let shared = InMemoryCredentialStore(credential: newer)
    let app = InMemoryCredentialStore(credential: manager)
    let store = StaffCredentialStore(shared: shared, app: app)
    #expect(try store.load() == newer)
    #expect(try app.load() == nil)
}

@Test func nextBorrowsTheProductionSessionUntilItHasItsOwn() throws {
    let production = InMemoryCredentialStore(credential: manager)
    let shared = InMemoryCredentialStore()
    let store = StaffCredentialStore(shared: shared, app: InMemoryCredentialStore(), trusted: production)
    #expect(try store.load() == manager)

    let own = makeCredential(token: "next")
    try store.save(own)
    #expect(try store.load() == own)
    #expect(try production.load() == manager, "a sign-in on Next never replaces production's")

    try store.delete()
    #expect(try store.load() == manager)
    try store.delete()
    #expect(try production.load() == nil, "signing out of a borrowed session ends it on production too")
    #expect(StaffKeychain.trusted(by: .staging) == .production)
    #expect(StaffKeychain.trusted(by: .production) == nil)
    #expect(ManagementPlatform.next.trustedCredentialOrigins == [ManagementPlatform.production.baseURL])
}

@Test func nextOpensOnProductionsAudienceUntilOneIsChosen() throws {
    let production = InMemoryAudienceStore(audience: ManagedAudience(id: "hot-mess", name: "Hot Mess", subdomain: "hotmess"))
    let store = StaffAudienceStore(own: InMemoryAudienceStore(), trusted: production)
    #expect(try store.load()?.id == "hot-mess")
    try store.save(ManagedAudience(id: "other", name: "Other", subdomain: "other"))
    #expect(try store.load()?.id == "other")
    #expect(try production.load()?.id == "hot-mess")
}

@Test func venueDeviceCredentialsAreRecognised() {
    #expect(StaffKeychain.isVenueDevice(device))
    #expect(!StaffKeychain.isVenueDevice(manager))
    #expect(StaffKeychain.service(for: .production) != StaffKeychain.service(for: .staging))
}

@Test func choosingAnAudienceRemembersItForTheSiblingApps() async throws {
    let stub = Stub { request in
        if request.path == "/v1/admin/choices" {
            return .json(status: 200, body: tokenJSON(makeCredential(token: "hot-mess-token", audienceID: "hot-mess", on: request.url)))
        }
        return .json(status: 200, body: #"{"data":{"me":{"cover":{"doorVenues":{"nodes":[]}}}}}"#)
    }
    let credentials = InMemoryCredentialStore(credential: makeCredential(token: "platform-token"))
    let audiences = InMemoryAudienceStore()
    let first = AudienceManagementSession(baseURL: stub.baseURL, environment: .staging, credentialStore: credentials,
                                          audienceStore: audiences, session: stub.session)
    let hotMess = ManagedAudience(id: "hot-mess", name: "Hot Mess", subdomain: "hotmess")
    #expect(await first.restoreAudience() == nil)
    try await first.choose(hotMess)
    #expect(try audiences.load() == hotMess)
    #expect(try credentials.load()?.token == "hot-mess-token")

    // Another staff app, same keychain group, next launch: no second swap of the server session.
    let sibling = AudienceManagementSession(baseURL: stub.baseURL, environment: .staging, credentialStore: credentials,
                                            audienceStore: audiences, session: stub.session)
    let requests = stub.requests.count
    #expect(await sibling.restoreAudience() == hotMess)
    #expect(stub.requests.count == requests)
    #expect(await sibling.boundAudienceID == "hot-mess")
    _ = try await VenueManagementClient(session: sibling).venues()
    #expect(try #require(stub.requests.last).path == "/v1/audience/hot-mess/staffql")

    try await sibling.signOut()
    #expect(try audiences.load() == nil)
    #expect(try credentials.load() == nil)
    #expect(await first.restoreAudience() == nil)
}

@Test func aVenueDeviceNeverRestoresASharedAudience() async {
    let audiences = InMemoryAudienceStore(audience: ManagedAudience(id: "hot-mess", name: "Hot Mess", subdomain: "hotmess"))
    let session = AudienceManagementSession(environment: .staging, credentialStore: InMemoryCredentialStore(credential: device),
                                            audienceStore: audiences)
    #expect(await session.restoreAudience() == nil)
    #expect(await session.isVenueDevice)
}
