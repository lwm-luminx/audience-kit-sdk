import Foundation

/// A "Check the app" run: the app's own list of everything it reads, one step at a time, with what each returned or
/// why it failed, so a broken screen can be traced to the call behind it. ``AppCheckView`` (AudienceKitUI) shows one
/// and copies its ``report(title:log:)``.
///
/// The app writes the steps, since only it knows what its screens load; a later step can use what an earlier one found:
///
/// ```swift
/// AppCheckView(title: "Hack Different 1.4", log: operationLog) { check in
///     await check.step("Signed in") { try await session.me().map { "As \($0.name)." } }
///     var localeID: String?
///     await check.step("Closest locale") {
///         let locale = try await session.closestLocale(near: position)
///         localeID = locale?.id
///         return locale?.name
///     }
///     ...
/// }
/// ```
@MainActor
public final class AppCheck {
    public struct Step: Identifiable, Sendable, Hashable {
        public enum Outcome: String, Sendable, Hashable {
            /// It worked and found something.
            case ok
            /// It worked and found nothing: often the reason a screen is empty.
            case empty
            /// It threw.
            case failed
            /// The app didn't run it (``AppCheck/skip(_:because:)``), usually because an earlier step found nothing.
            case skipped
        }

        public let id: UUID
        public let name: String
        public let outcome: Outcome
        public let detail: String
        public let milliseconds: Int

        public init(id: UUID = UUID(), name: String, outcome: Outcome, detail: String, milliseconds: Int) {
            self.id = id
            self.name = name
            self.outcome = outcome
            self.detail = detail
            self.milliseconds = milliseconds
        }

        public var mark: String {
            switch outcome {
            case .ok: "OK"
            case .empty: "EMPTY"
            case .failed: "FAIL"
            case .skipped: "SKIP"
            }
        }
    }

    /// An error a step throws to fail with a plain sentence ("Location is denied for this app.").
    public struct Problem: LocalizedError, CustomStringConvertible, Sendable {
        public let description: String
        public init(_ description: String) { self.description = description }
        public var errorDescription: String? { description }
    }

    public private(set) var steps: [Step] = []
    public private(set) var isRunning = false
    /// Called after every change, for a view to redraw.
    public var onChange: (() -> Void)?

    public init() {}

    public var hasFailures: Bool { steps.contains { $0.outcome == .failed } }

    /// Clears the steps and runs `checks`. A run already going is left to finish and this one is ignored.
    public func run(_ checks: (AppCheck) async -> Void) async {
        guard !isRunning else { return }
        isRunning = true
        steps = []
        onChange?()
        await checks(self)
        isRunning = false
        onChange?()
    }

    /// Times one step. `body` returns a one-line summary of what it found, or nil when it found nothing.
    @discardableResult
    public func step(_ name: String, _ body: () async throws -> String?) async -> Step.Outcome {
        let started = ContinuousClock.now
        let outcome: Step.Outcome
        let detail: String
        do {
            if let summary = try await body() {
                (outcome, detail) = (.ok, summary)
            } else {
                (outcome, detail) = (.empty, "Nothing came back.")
            }
        } catch {
            (outcome, detail) = (.failed, Self.describe(error))
        }
        append(Step(name: name, outcome: outcome, detail: detail,
                    milliseconds: GraphQLOperationLog.milliseconds(ContinuousClock.now - started)))
        return outcome
    }

    /// Records a step that wasn't run, and why.
    public func skip(_ name: String, because reason: String) {
        append(Step(name: name, outcome: .skipped, detail: reason, milliseconds: 0))
    }

    /// Everything on one plain-text page for a bug report: the title line (app, version, server), each step, then the
    /// log's recent failed requests.
    public func report(title: String, log: GraphQLOperationLog? = nil) -> String {
        var lines = [title]
        lines += steps.map { "\($0.mark) \($0.name) (\($0.milliseconds) ms): \($0.detail)" }
        let failures = log?.failures() ?? []
        if !failures.isEmpty {
            lines.append("Failed requests:")
            lines += failures.reversed().map { "- \($0.name): \($0.error ?? "")" }
        }
        return lines.joined(separator: "\n")
    }

    private func append(_ step: Step) {
        steps.append(step)
        onChange?()
    }

    /// The error's own sentence where it has one, else its description, so GraphQL errors read as the server put them.
    nonisolated static func describe(_ error: any Error) -> String {
        if let localized = (error as? LocalizedError)?.errorDescription, !localized.isEmpty { return localized }
        return String(describing: error)
    }
}
