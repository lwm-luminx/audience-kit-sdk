import Foundation

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// App Review sign-in: the code a store's review notes give the reviewer, which signs in the audience's review
/// account (`POST /v1/token/review`). Apps offer it as "Have an App Review code?" only when
/// ``AudienceSession/reviewCodeAvailable(installSource:)`` says so, which is never in an App Store install.
extension AudienceSession {
    /// Whether to offer App Review sign-in now: not in an App Store install (``InstallSource/offersReviewCode``), and
    /// otherwise only while the API takes codes for the audience (`GET /v1/token/review`, on while the audience is in
    /// App Review). False when the API can't be reached.
    ///
    /// - Parameter installSource: where this copy came from; ``InstallSource/current`` by default.
    public func reviewCodeAvailable(installSource: InstallSource? = nil) async -> Bool {
        let source: InstallSource
        if let installSource { source = installSource } else { source = await InstallSource.current }
        guard source.offersReviewCode else { return false }

        let query = configuration.host.map { [URLQueryItem(name: "host", value: $0)] } ?? []
        let request = APIRequest(path: "/v1/token/review", queryItems: query, authenticated: false)
        guard let data = try? await data(for: request),
              let status = try? JSONDecoder().decode(ReviewCodeStatus.self, from: data)
        else { return false }
        return status.enabled ?? false
    }

    /// Signs in with an App Review code and stores the session, like the other sign-ins. Sends this install's signed
    /// AppTransaction, so the API refuses the code in an App Store install (``AudienceKitError/forbidden`` with reason
    /// `store_install`). A wrong or expired code, or App Review being off, throws ``AudienceKitError/signInRejected``.
    ///
    /// - Parameter appTransaction: the signed AppTransaction to send; ``InstallSource/signedAppTransaction`` by
    ///   default.
    @discardableResult
    public func signIn(reviewCode: String, device: DeviceDescription, appTransaction: String? = nil) async throws
        -> SignInResult
    {
        let signed: String?
        if let appTransaction { signed = appTransaction } else { signed = await InstallSource.signedAppTransaction }
        let body = ReviewSignInRequest(code: reviewCode.trimmingCharacters(in: .whitespacesAndNewlines),
                                       host: configuration.host, device: device, appTransaction: signed)
        return try await signIn(path: "/v1/token/review", body: try JSONEncoder().encode(body), authenticated: false)
    }
}

/// `GET /v1/token/review`'s answer.
struct ReviewCodeStatus: Decodable {
    var enabled: Bool?
}

/// `POST /v1/token/review`'s body.
struct ReviewSignInRequest: Encodable {
    var code: String
    var host: String?
    var device: DeviceDescription
    var appTransaction: String?

    enum CodingKeys: String, CodingKey {
        case code, host, device
        case appTransaction = "app_transaction"
    }
}
