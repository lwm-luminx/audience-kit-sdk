import Foundation
import Testing
@testable import AudienceCore
@testable import AudienceKit

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

private func reviewClient(_ stub: Stub) -> AudienceKitClient {
    let configuration = AudienceKitConfiguration(baseURL: stub.baseURL, host: "hotmess.social", audienceID: "a-1")
    return AudienceKitClient(configuration: configuration, credentialStore: InMemoryCredentialStore(),
                             session: stub.session, deviceAttestor: nil)
}

private func reviewTokenJSON(_ request: RecordedRequest) -> String {
    let base = "\(request.url.scheme!)://\(request.url.host!)"
    return #"{"token":"jwt-1","userId":"u-1","audienceId":"a-1","role":"member","endpoint":"\#(base)/v1/audiences/a-1/graphql","venueDeviceId":null,"expiresAt":null}"#
}

@Suite struct ReviewCodeTests {
    @Test func appStoreInstallsNeverOfferTheCode() {
        #expect(!InstallSource.appStore.offersReviewCode)
        #expect(InstallSource.testFlight.offersReviewCode)
        #expect(InstallSource.development.offersReviewCode)
        #expect(InstallSource.unknown.offersReviewCode)
    }

    @Test func offersTheCodeWhileTheAPISaysSoOutsideTheAppStore() async throws {
        let stub = Stub { _ in .json(status: 200, body: #"{"enabled":true}"#) }
        let session = reviewClient(stub)

        #expect(await session.reviewCodeAvailable(installSource: .testFlight))
        let asked = try #require(stub.requests.first)
        #expect(asked.method == "GET")
        #expect(asked.path == "/v1/token/review")
        #expect(asked.url.query?.contains("host=hotmess.social") == true)

        #expect(await !session.reviewCodeAvailable(installSource: .appStore))
        #expect(stub.requests.count == 1)
    }

    @Test func hidesTheCodeWhenTheAPISaysNoOrFails() async {
        let off = Stub { _ in .json(status: 200, body: #"{"enabled":false}"#) }
        #expect(await !reviewClient(off).reviewCodeAvailable(installSource: .testFlight))
        let down = Stub { _ in .json(status: 500, body: "{}") }
        #expect(await !reviewClient(down).reviewCodeAvailable(installSource: .unknown))
    }

    @Test func signsInWithTheCodeAndTheAppTransaction() async throws {
        let stub = Stub { request in .json(status: 200, body: reviewTokenJSON(request)) }
        let session = reviewClient(stub)

        let result = try await session.signIn(reviewCode: " ABCD-EFGH-IJKL-MNOP\n",
                                              device: DeviceDescription(identifier: "device-1"),
                                              appTransaction: "signed.app.transaction")
        #expect(result.credential.token == "jwt-1")
        let posted = try #require(stub.requests.last)
        #expect(posted.method == "POST")
        #expect(posted.path == "/v1/token/review")
        let body = try posted.jsonBody()
        #expect(body["code"] as? String == "ABCD-EFGH-IJKL-MNOP")
        #expect(body["host"] as? String == "hotmess.social")
        #expect(body["app_transaction"] as? String == "signed.app.transaction")
    }

    @Test func aStoreInstallIsRefused() async {
        let stub = Stub { _ in
            .json(status: 403, body: #"{"error":"FORBIDDEN","message":"App Review codes don't work in an app installed from the App Store","reason":"store_install"}"#)
        }
        await #expect(throws: AudienceKitError.self) {
            try await reviewClient(stub).signIn(reviewCode: "ABCD", device: DeviceDescription(identifier: "d"),
                                                appTransaction: "signed")
        }
    }

    @Test func aWrongCodeIsRejected() async {
        let stub = Stub { _ in .json(status: 401, body: #"{"error":"UNAUTHENTICATED","message":"Code is invalid or expired"}"#) }
        await #expect(throws: AudienceKitError.signInRejected) {
            try await reviewClient(stub).signIn(reviewCode: "ABCD", device: DeviceDescription(identifier: "d"),
                                                appTransaction: "signed")
        }
    }
}
