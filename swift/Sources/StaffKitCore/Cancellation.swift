import Foundation
import AudienceCore

extension Error {
    /// Whether this is a cancelled request rather than a failure: the task was cancelled (a pull-to-refresh or
    /// `.task` that SwiftUI tore down, a screen that went away), so there's nothing to tell the person.
    ///
    /// The SDK wraps the `URLError.cancelled` a cancelled task's request fails with in an `AudienceKitError`
    /// (`NETWORK`, message "cancelled"), so a `catch is CancellationError` alone doesn't see it.
    public var isCancellation: Bool {
        if self is CancellationError { return true }
        if let error = self as? AudienceKitError { return error.underlying?.code == .cancelled }
        if let error = self as? URLError { return error.code == .cancelled }
        let error = self as NSError
        return error.domain == NSURLErrorDomain && error.code == NSURLErrorCancelled
    }
}
