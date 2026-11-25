import Foundation
#if canImport(StoreKit)
import StoreKit
#endif

/// The install's AppTransaction as Apple signed it, sent with App Review sign-ins so the API can refuse the code in a
/// copy from the App Store (audience_kit_api's AppReviewInstall).
enum ReviewInstall {
    /// `AppTransaction.shared.jwsRepresentation`, verified or not (the API checks the signature); nil when StoreKit has
    /// none.
    static func signedAppTransaction() async -> String? {
        #if canImport(StoreKit)
        guard let result = try? await AppTransaction.shared else { return nil }
        return result.jwsRepresentation
        #else
        return nil
        #endif
    }
}
