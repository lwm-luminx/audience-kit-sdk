#if canImport(SwiftUI)
import AudienceKit
import SwiftUI

/// "Delete Account" for a profile or settings screen (App Store guideline 5.1.1(v)): asks first, then calls
/// ``AudienceSession/deleteAccount()``. On success the client yields ``SessionEvent/signedOut``, so an app that already
/// shows sign-in on that event needs nothing else; `onDeleted` runs after it for anything app-specific (clearing
/// caches, logging out of Facebook).
///
/// ```swift
/// Section { DeleteAccountButton(client: client, appName: "Hack Different") }
/// ```
public struct DeleteAccountButton: View {
    let client: AudienceKitClient
    let appName: String
    let onDeleted: @MainActor () async -> Void
    @State private var confirming = false
    @State private var working = false
    @State private var error: String?

    public init(client: AudienceKitClient, appName: String,
                onDeleted: @escaping @MainActor () async -> Void = {}) {
        self.client = client
        self.appName = appName
        self.onDeleted = onDeleted
    }

    public var body: some View {
        Button(role: .destructive) {
            confirming = true
        } label: {
            HStack {
                SwiftUI.Label("Delete Account", systemImage: "person.crop.circle.badge.xmark")
                if working {
                    Spacer()
                    ProgressView()
                }
            }
        }
        .disabled(working)
        .confirmationDialog("Delete your \(appName) account?", isPresented: $confirming, titleVisibility: .visible) {
            Button("Delete Account", role: .destructive) { Task { await delete() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(DeleteAccountCopy.warning)
        }
        .alert("Couldn't delete your account",
               isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(error ?? "")
        }
    }

    private func delete() async {
        working = true
        defer { working = false }
        do {
            if try await client.deleteAccount() {
                await onDeleted()
            } else {
                error = DeleteAccountCopy.notDeleted
            }
        } catch {
            self.error = error.localizedDescription
        }
    }
}

/// The words around account deletion, shared with Android so both apps say the same thing.
public enum DeleteAccountCopy {
    public static let warning = "This deletes your account in every app built on AudienceKit, including Hot Mess "
        + "and Hack Different, along with any staff or admin roles you have. Your profile, messages, RSVPs and passes "
        + "go too, and you're signed out on every device. It can't be undone."
    public static let notDeleted = "Your account is still here. Try again, or email hello@audiencekit.com."
}
#endif
