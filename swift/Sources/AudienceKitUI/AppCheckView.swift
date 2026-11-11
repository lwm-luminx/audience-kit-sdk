#if canImport(SwiftUI)
import AudienceCore
import AudienceKit
import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// "Check the app", for an app's Me or Settings screen: runs the app's own checks (``AppCheck``) as the signed-in
/// person, shows what each step found or why it failed, lists the recent failed requests from a
/// ``GraphQLOperationLog``, and copies a plain-text report for a bug. Nothing is changed by running it.
///
/// ```swift
/// NavigationLink("Check the app") {
///     AppCheckView(title: "Hack Different \(version), \(baseURL)", log: model.operations) { check in
///         await check.step("Signed in") { try await client.me().map { "As \($0.displayName)." } }
///         await check.step("Upcoming events") {
///             let events = try await client.events(window: .upcoming, first: 10)
///             return events.isEmpty ? nil : "\(events.count) upcoming."
///         }
///     }
/// }
/// ```
public struct AppCheckView: View {
    let title: String
    let log: GraphQLOperationLog?
    let checks: @MainActor (AppCheck) async -> Void
    @StateObject private var model = Model()

    /// - Parameters:
    ///   - title: The report's first line: the app, its version and the server it talks to.
    ///   - log: Where recent failed requests come from.
    ///   - checks: The steps, in order; see ``AppCheck/step(_:_:)``.
    public init(title: String, log: GraphQLOperationLog? = nil,
                checks: @escaping @MainActor (AppCheck) async -> Void) {
        self.title = title
        self.log = log
        self.checks = checks
    }

    public var body: some View {
        List {
            Section {
                Button(model.check.isRunning ? "Checking…" : (model.check.steps.isEmpty ? "Run the check" : "Run it again")) {
                    Task { await model.check.run(checks) }
                }
                .disabled(model.check.isRunning)
                if !model.check.steps.isEmpty {
                    Button("Copy report") { AppCheckPasteboard.copy(model.check.report(title: title, log: log)) }
                }
            } footer: {
                Text("Runs each thing the app loads, as you. Nothing is changed.")
            }
            if !model.check.steps.isEmpty {
                Section("Results") {
                    ForEach(model.check.steps) { step in
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Image(systemName: Self.icon(step.outcome)).foregroundStyle(Self.color(step.outcome))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(step.name).font(.subheadline.weight(.semibold))
                                Text(step.detail).font(.footnote).foregroundStyle(.secondary).textSelection(.enabled)
                            }
                            Spacer()
                            Text("\(step.milliseconds) ms").font(.caption2.monospacedDigit()).foregroundStyle(.tertiary)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }
            let failures = log?.failures() ?? []
            if !failures.isEmpty {
                Section("Recent failed requests") {
                    ForEach(failures) { entry in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.name).font(.subheadline.weight(.semibold))
                            Text(entry.error ?? "").font(.footnote).foregroundStyle(.secondary).textSelection(.enabled)
                        }
                    }
                }
            }
        }
        .navigationTitle("Check the app")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    static func icon(_ outcome: AppCheck.Step.Outcome) -> String {
        switch outcome {
        case .ok: "checkmark.circle.fill"
        case .empty: "circle.dashed"
        case .failed: "xmark.octagon.fill"
        case .skipped: "arrow.uturn.right.circle"
        }
    }

    static func color(_ outcome: AppCheck.Step.Outcome) -> Color {
        switch outcome {
        case .ok: .green
        case .empty: .orange
        case .failed: .red
        case .skipped: .secondary
        }
    }

    @MainActor
    final class Model: ObservableObject {
        let check = AppCheck()

        init() {
            check.onChange = { [weak self] in self?.objectWillChange.send() }
        }
    }
}

enum AppCheckPasteboard {
    static func copy(_ text: String) {
        #if canImport(UIKit) && !os(watchOS) && !os(tvOS)
        UIPasteboard.general.string = text
        #elseif canImport(AppKit)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #endif
    }
}
#endif
