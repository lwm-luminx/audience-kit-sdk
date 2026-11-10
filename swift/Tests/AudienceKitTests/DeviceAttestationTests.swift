import Foundation
import Testing
@testable import AudienceCore
@testable import AudienceKit

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// App Attest stand-in: records what it was asked and answers fixed bytes.
private final class FakeAppAttest: AppAttestService, @unchecked Sendable {
    private let lock = NSLock()
    var supported = true
    var assertionFails = false
    private(set) var generated: [String] = []
    private(set) var hashes: [Data] = []

    var isSupported: Bool { supported }

    func generateKey() async throws -> String {
        lock.withLock {
            let key = "key-\(generated.count + 1)"
            generated.append(key)
            return key
        }
    }

    func attestKey(_ keyID: String, clientDataHash: Data) async throws -> Data {
        lock.withLock { hashes.append(clientDataHash) }
        return Data("attestation-\(keyID)".utf8)
    }

    func generateAssertion(_ keyID: String, clientDataHash: Data) async throws -> Data {
        lock.withLock { hashes.append(clientDataHash) }
        if assertionFails { throw URLError(.unknown) }
        return Data("assertion-\(keyID)".utf8)
    }
}

private final class MemoryKeyStore: AttestationKeyStore, @unchecked Sendable {
    private let lock = NSLock()
    private var keyID: String?
    init(_ keyID: String? = nil) { self.keyID = keyID }
    func loadKeyID() -> String? { lock.withLock { keyID } }
    func saveKeyID(_ keyID: String?) { lock.withLock { self.keyID = keyID } }
}

private let device = DeviceDescription(identifier: "device-1")

private func tokenJSON(_ request: RecordedRequest) -> String {
    let base = "\(request.url.scheme!)://\(request.url.host!)"
    return #"{"token":"jwt-1","userId":"u-1","audienceId":"a-1","role":"member","endpoint":"\#(base)/v1/audiences/a-1/graphql","venueDeviceId":null,"expiresAt":null}"#
}

private func challengeJSON(_ value: String, mode: String = "enforce") -> String {
    #"{"challenge":"\#(value)","expiresAt":"2026-11-10T20:00:00Z","mode":"\#(mode)"}"#
}

private func client(_ stub: Stub, attestor: (any DeviceAttestor)?) -> AudienceKitClient {
    let configuration = AudienceKitConfiguration(baseURL: stub.baseURL, host: "hotmess.social", audienceID: "a-1")
    return AudienceKitClient(configuration: configuration, credentialStore: InMemoryCredentialStore(),
                             session: stub.session, deviceAttestor: attestor)
}

@Suite struct DeviceAttestationTests {
    @Test func attestsANewKeyThenAssertsWithIt() async throws {
        let challenges = Counter()
        let stub = Stub { request in
            if request.path == "/v1/token/attestation" { return .json(status: 200, body: challengeJSON("c-\(challenges.next())")) }
            return .json(status: 200, body: tokenJSON(request))
        }
        let service = FakeAppAttest()
        let store = MemoryKeyStore()
        let session = client(stub, attestor: AppAttestAttestor(service: service, keyStore: store))

        try await session.signIn(appleIdentityToken: "apple-jwt", device: device)
        try await session.signIn(appleIdentityToken: "apple-jwt", device: device)

        let signIns = stub.requests.filter { $0.path == "/v1/token/apple" }
        let first = try #require(try signIns[0].jsonBody()["attestation"] as? [String: Any])
        #expect(first["platform"] as? String == "ios")
        #expect(first["challenge"] as? String == "c-1")
        #expect(first["key_id"] as? String == "key-1")
        #expect(first["attestation"] as? String == Data("attestation-key-1".utf8).base64EncodedString())
        #expect(first["assertion"] == nil)
        let second = try #require(try signIns[1].jsonBody()["attestation"] as? [String: Any])
        #expect(second["challenge"] as? String == "c-2")
        #expect(second["assertion"] as? String == Data("assertion-key-1".utf8).base64EncodedString())
        #expect(store.loadKeyID() == "key-1")
        // clientDataHash is SHA-256 of the challenge's UTF-8 bytes.
        #expect(service.hashes.first == SHA256Hex.data("c-1"))
        #expect(service.hashes.first?.count == 32)
    }

    @Test func makesANewKeyWhenTheAPIDoesNotKnowTheOldOne() async throws {
        let refusals = Counter()
        let stub = Stub { request in
            if request.path == "/v1/token/attestation" { return .json(status: 200, body: challengeJSON("c")) }
            if refusals.next() == 1 {
                return .json(status: 403, body: #"{"error":"FORBIDDEN","message":"no","reason":"attestation_key_unknown"}"#)
            }
            return .json(status: 200, body: tokenJSON(request))
        }
        let service = FakeAppAttest()
        let session = client(stub, attestor: AppAttestAttestor(service: service, keyStore: MemoryKeyStore("old")))

        let result = try await session.signIn(appleIdentityToken: "apple-jwt", device: device)

        #expect(result.userId == "u-1")
        let signIns = stub.requests.filter { $0.path == "/v1/token/apple" }
        #expect(signIns.count == 2)
        let retry = try #require(try signIns[1].jsonBody()["attestation"] as? [String: Any])
        #expect(retry["key_id"] as? String == "key-1")
        #expect(retry["attestation"] != nil)
    }

    @Test func throwsDeviceNotTrustedWhenRefused() async throws {
        let stub = Stub { request in
            if request.path == "/v1/token/attestation" { return .json(status: 200, body: challengeJSON("c")) }
            return .json(status: 403, body: #"{"error":"FORBIDDEN","message":"Only the real app","reason":"device_not_trusted"}"#)
        }
        let session = client(stub, attestor: AppAttestAttestor(service: FakeAppAttest(), keyStore: MemoryKeyStore()))

        await #expect(throws: AudienceKitError.deviceNotTrusted(message: "Only the real app")) {
            try await session.signIn(appleIdentityToken: "apple-jwt", device: device)
        }
    }

    @Test func saysWhyWhenItCannotAttest() async throws {
        let stub = Stub { request in .json(status: 200, body: tokenJSON(request)) }
        let service = FakeAppAttest()
        service.supported = false
        let session = client(stub, attestor: AppAttestAttestor(service: service, keyStore: MemoryKeyStore()))

        try await session.signIn(appleIdentityToken: "apple-jwt", device: device)

        #expect(stub.requests.map(\.path) == ["/v1/token/apple"])
        let proof = try #require(try stub.requests[0].jsonBody()["attestation"] as? [String: Any])
        #expect(proof["unsupported"] as? Bool == true)
        // `simulator` when the tests run in one (Xcode Cloud), `unsupported` elsewhere.
        #expect(["unsupported", "simulator"].contains(proof["reason"] as? String))
    }

    @Test func skipsTheWorkWhenTheAudienceHasItOffOrTheAPIIsOlder() async throws {
        let stub = Stub { request in
            if request.path == "/v1/token/attestation" { return .json(status: 200, body: challengeJSON("c", mode: "off")) }
            return .json(status: 200, body: tokenJSON(request))
        }
        let service = FakeAppAttest()
        try await client(stub, attestor: AppAttestAttestor(service: service, keyStore: MemoryKeyStore()))
            .signIn(appleIdentityToken: "apple-jwt", device: device)
        #expect(try stub.requests.last?.jsonBody()["attestation"] == nil)
        #expect(service.generated.isEmpty)

        let older = Stub { request in
            if request.path == "/v1/token/attestation" { return .json(status: 404, body: "{}") }
            return .json(status: 200, body: tokenJSON(request))
        }
        try await client(older, attestor: AppAttestAttestor(service: service, keyStore: MemoryKeyStore()))
            .signIn(appleIdentityToken: "apple-jwt", device: device)
        #expect(try older.requests.last?.jsonBody()["attestation"] == nil)
    }

    @Test func fallsBackToANewKeyWhenTheStoredOneIsGone() async throws {
        let service = FakeAppAttest()
        service.assertionFails = true
        let store = MemoryKeyStore("restored-from-backup")
        let attestor = AppAttestAttestor(service: service, keyStore: store)

        let proof = try await attestor.attest(challenge: "c")

        #expect(proof.keyID == "key-1")
        #expect(proof.attestation != nil)
        #expect(store.loadKeyID() == "key-1")
        await attestor.forgetKey()
        #expect(store.loadKeyID() == nil)
    }

    @Test func encodesTheWireNames() throws {
        let proof = DeviceAttestation(platform: "android", challenge: "c", packageName: "p", token: "t")
        let json = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(proof)) as? [String: Any])
        #expect(json["package_name"] as? String == "p")
        #expect(json["token"] as? String == "t")
        #expect(SHA256Hex.digest("abc") == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        #expect(SHA256Hex.data("abc").map { String(format: "%02x", $0) }.joined() == SHA256Hex.digest("abc"))
    }

    @Test func keepsTheKeyIDInUserDefaults() {
        let defaults = UserDefaults(suiteName: "attestation-\(UUID().uuidString)")!
        let store = UserDefaultsAttestationKeyStore(defaults: defaults)
        #expect(store.loadKeyID() == nil)
        store.saveKeyID("k")
        #expect(store.loadKeyID() == "k")
        store.saveKeyID(nil)
        #expect(store.loadKeyID() == nil)
    }
}

/// A thread-safe counter for stub handlers: 1, 2, 3…
private final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    func next() -> Int { lock.withLock { value += 1; return value } }
}
