import Foundation

#if canImport(DeviceCheck)
import DeviceCheck
#endif

/// What ``AppAttestAttestor`` needs from Apple's App Attest service (`DCAppAttestService`), so tests can stand in.
public protocol AppAttestService: Sendable {
    var isSupported: Bool { get }
    func generateKey() async throws -> String
    func attestKey(_ keyID: String, clientDataHash: Data) async throws -> Data
    func generateAssertion(_ keyID: String, clientDataHash: Data) async throws -> Data
}

/// Where ``AppAttestAttestor`` keeps its key's identifier. The key itself never leaves the Secure Enclave.
public protocol AttestationKeyStore: Sendable {
    func loadKeyID() -> String?
    func saveKeyID(_ keyID: String?)
}

/// Keeps the key identifier in `UserDefaults`. A restored backup carries it to a device where the key doesn't exist;
/// App Attest then refuses it and the attestor makes a new one.
public struct UserDefaultsAttestationKeyStore: AttestationKeyStore, @unchecked Sendable {
    private let defaults: UserDefaults
    private let key: String

    public init(defaults: UserDefaults = .standard, key: String = "com.audiencekit.appAttestKeyID") {
        self.defaults = defaults
        self.key = key
    }

    public func loadKeyID() -> String? { defaults.string(forKey: key) }

    public func saveKeyID(_ keyID: String?) {
        if let keyID { defaults.set(keyID, forKey: key) } else { defaults.removeObject(forKey: key) }
    }
}

/// Apple App Attest for sign-ins. The first sign-in from an install makes a key in the Secure Enclave and has Apple
/// attest it; later ones sign an assertion with that key, which is cheaper and not rate limited. Each proof covers
/// the API's one-use challenge: `clientDataHash` is SHA-256 of the challenge's UTF-8 bytes.
///
/// ``AudienceSession`` uses one by default on iOS. Simulators and Macs can't attest; they sign in without proof
/// (`unsupported`), which only an audience that enforces attestation refuses. Builds run from Xcode attest in Apple's
/// development environment, which the API accepts only for the audience's non-production app records.
public actor AppAttestAttestor: DeviceAttestor {
    private let service: any AppAttestService
    private let keyStore: any AttestationKeyStore

    public init(service: any AppAttestService, keyStore: any AttestationKeyStore = UserDefaultsAttestationKeyStore()) {
        self.service = service
        self.keyStore = keyStore
    }

    public func unsupportedReason() async -> String? {
        service.isSupported ? nil : (Self.isSimulator ? "simulator" : "unsupported")
    }

    public func attest(challenge: String) async throws -> DeviceAttestation {
        if let reason = await unsupportedReason() { return .unsupported(platform: "ios", reason: reason) }
        let clientDataHash = SHA256Hex.data(challenge)

        if let keyID = keyStore.loadKeyID() {
            do {
                let assertion = try await service.generateAssertion(keyID, clientDataHash: clientDataHash)
                return DeviceAttestation(platform: "ios", challenge: challenge, keyID: keyID,
                                         assertion: assertion.base64EncodedString())
            } catch {
                // The key is gone (a restored backup, a reset Secure Enclave): make a new one below.
                keyStore.saveKeyID(nil)
            }
        }

        let keyID = try await service.generateKey()
        let attestation = try await service.attestKey(keyID, clientDataHash: clientDataHash)
        keyStore.saveKeyID(keyID)
        return DeviceAttestation(platform: "ios", challenge: challenge, keyID: keyID,
                                 attestation: attestation.base64EncodedString())
    }

    public func forgetKey() async {
        keyStore.saveKeyID(nil)
    }

    static var isSimulator: Bool {
        #if targetEnvironment(simulator)
        true
        #else
        false
        #endif
    }
}

#if canImport(DeviceCheck) && !os(watchOS)
/// `DCAppAttestService.shared`.
@available(iOS 14.0, macOS 11.0, tvOS 15.0, *)
public struct DeviceCheckAppAttestService: AppAttestService {
    public init() {}

    public var isSupported: Bool { DCAppAttestService.shared.isSupported }

    public func generateKey() async throws -> String {
        try await DCAppAttestService.shared.generateKey()
    }

    public func attestKey(_ keyID: String, clientDataHash: Data) async throws -> Data {
        try await DCAppAttestService.shared.attestKey(keyID, clientDataHash: clientDataHash)
    }

    public func generateAssertion(_ keyID: String, clientDataHash: Data) async throws -> Data {
        try await DCAppAttestService.shared.generateAssertion(keyID, clientDataHash: clientDataHash)
    }
}
#endif

extension AppAttestAttestor {
    /// The attestor ``AudienceSession`` uses unless the app passes its own: App Attest on iOS, none elsewhere.
    public static var platformDefault: (any DeviceAttestor)? {
        #if os(iOS) && canImport(DeviceCheck)
        AppAttestAttestor(service: DeviceCheckAppAttestService())
        #else
        nil
        #endif
    }
}
