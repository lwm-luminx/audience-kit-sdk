import Foundation

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Proof that a sign-in comes from the audience's genuine app on a genuine device, sent with every sign-in as
/// `attestation` (the API's doc/DEVICE_ATTESTATION.md). On iOS it's App Attest (``AppAttestAttestor``); the Android
/// SDK sends Play Integrity. Each audience decides whether the API only records it or refuses sign-ins without it.
public struct DeviceAttestation: Codable, Sendable, Hashable {
    /// `ios` or `android`.
    public var platform: String
    /// The one-use challenge from `POST /v1/token/attestation` this proof covers.
    public var challenge: String?
    /// App Attest: the key's identifier, as `DCAppAttestService.generateKey()` returned it.
    public var keyID: String?
    /// App Attest: the attestation object of a new key, Base64.
    public var attestation: String?
    /// App Attest: an assertion signed with a key the API already knows, Base64.
    public var assertion: String?
    /// Play Integrity: the app's package name and the integrity token.
    public var packageName: String?
    public var token: String?
    /// The device can't attest (a simulator, an older OS, the service failing); ``reason`` says why.
    public var unsupported: Bool?
    public var reason: String?

    public init(platform: String, challenge: String? = nil, keyID: String? = nil, attestation: String? = nil,
                assertion: String? = nil, packageName: String? = nil, token: String? = nil,
                unsupported: Bool? = nil, reason: String? = nil)
    {
        self.platform = platform
        self.challenge = challenge
        self.keyID = keyID
        self.attestation = attestation
        self.assertion = assertion
        self.packageName = packageName
        self.token = token
        self.unsupported = unsupported
        self.reason = reason
    }

    /// A device that can't attest, and why (a short word: `simulator`, `unsupported`, `attest_failed`…).
    public static func unsupported(platform: String, reason: String) -> DeviceAttestation {
        DeviceAttestation(platform: platform, unsupported: true, reason: reason)
    }

    enum CodingKeys: String, CodingKey {
        case platform, challenge, attestation, assertion, token, unsupported, reason
        case keyID = "key_id"
        case packageName = "package_name"
    }
}

/// Signs a sign-in challenge on this device. ``AudienceSession`` asks for a challenge, hands it here and sends the
/// result with the sign-in; when the API says it doesn't know the key, it calls ``forgetKey()`` and tries once more.
public protocol DeviceAttestor: Sendable {
    /// Why this device can't attest at all (`simulator`, `unsupported`), or nil when it can. When it can't, the
    /// sign-in says so without asking the API for a challenge.
    func unsupportedReason() async -> String?
    /// Proof over `challenge`. Throwing, or answering ``DeviceAttestation/unsupported(platform:reason:)``, signs in
    /// without proof, which an audience that enforces attestation refuses.
    func attest(challenge: String) async throws -> DeviceAttestation
    /// Forgets the key, so the next ``attest(challenge:)`` makes and attests a new one.
    func forgetKey() async
}

/// `POST /v1/token/attestation`'s answer.
struct AttestationChallenge: Decodable, Sendable {
    var challenge: String
    /// `off`, `report` or `enforce`; absent from older APIs.
    var mode: String?
}

extension AudienceSession {
    /// Adds `attestation` to a sign-in body when the session has an attestor and the audience checks attestation.
    /// Never fails the sign-in: when anything goes wrong it sends why, and the API decides.
    func attested(_ body: Data) async -> Data {
        guard let attestor = deviceAttestor,
              var object = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any]
        else { return body }

        let proof: DeviceAttestation
        if let reason = await attestor.unsupportedReason() {
            proof = .unsupported(platform: Self.attestationPlatform, reason: reason)
        } else {
            do {
                guard let challenge = try await attestationChallenge(), challenge.mode != "off" else { return body }
                proof = try await attestor.attest(challenge: challenge.challenge)
            } catch {
                proof = .unsupported(platform: Self.attestationPlatform, reason: "attest_failed")
            }
        }
        guard let encoded = try? JSONSerialization.jsonObject(with: JSONEncoder().encode(proof)) else { return body }
        object["attestation"] = encoded
        return (try? JSONSerialization.data(withJSONObject: object)) ?? body
    }

    /// A fresh challenge for this audience's host; nil when the API doesn't offer attestation (an older API).
    private func attestationChallenge() async throws -> AttestationChallenge? {
        var body: [String: String] = [:]
        if let host = configuration.host { body["host"] = host }
        let request = APIRequest(method: "POST", path: "/v1/token/attestation",
                                 body: try JSONEncoder().encode(body), authenticated: false)
        let (data, response) = try await perform(request)
        guard (200 ..< 300).contains(response.statusCode) else { return nil }
        return try JSONDecoder().decode(AttestationChallenge.self, from: data)
    }

    /// The Swift SDK attests with App Attest; the Kotlin SDK sends `android`.
    static var attestationPlatform: String { "ios" }
}
