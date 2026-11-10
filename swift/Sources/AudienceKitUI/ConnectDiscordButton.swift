#if canImport(SwiftUI) && canImport(AuthenticationServices)
import AudienceKit
import AuthenticationServices
import SwiftUI

/// "Connect Discord" for a profile or settings screen: for someone who signed in another way (Sign in with Apple, say)
/// to connect their Discord account, so the audience's Discord bridge knows them and can show them its channels.
/// Shows "Discord: @username" once connected. Opens Discord's sign-in in an authentication session
/// (``AudienceSession/discordConnection(app:platform:)``), then connects with what the API sends back
/// (``AudienceSession/connectDiscord(callbackURL:connection:device:)``).
///
/// The app must be listed in the audience's console (Apps) for the API to send the answer back to it.
///
/// ```swift
/// Section { ConnectDiscordButton(client: client, device: device) }
/// ```
@available(iOS 16.4, macOS 13.3, *)
public struct ConnectDiscordButton: View {
    let client: AudienceKitClient
    let device: DeviceDescription
    let app: String
    let onConnected: @MainActor (ConnectedDiscord) async -> Void
    @Environment(\.webAuthenticationSession) private var webAuthenticationSession
    @State private var connected: ConnectedDiscord?
    @State private var working = false
    @State private var error: String?

    /// `app` is the bundle ID the API sends the answer back to: the running app's, unless it's listed under another.
    public init(client: AudienceKitClient, device: DeviceDescription, app: String? = Bundle.main.bundleIdentifier,
                onConnected: @escaping @MainActor (ConnectedDiscord) async -> Void = { _ in })
    {
        self.client = client
        self.device = device
        self.app = app ?? ""
        self.onConnected = onConnected
    }

    public var body: some View {
        Group {
            if let connected {
                LabeledContent(ConnectDiscordCopy.connectedLabel,
                               value: connected.username.map { "@\($0)" } ?? ConnectDiscordCopy.connected)
            } else {
                Button {
                    Task { await connect() }
                } label: {
                    HStack {
                        SwiftUI.Label(ConnectDiscordCopy.connect, systemImage: "bubble.left.and.bubble.right")
                        if working {
                            Spacer()
                            ProgressView()
                        }
                    }
                }
                .disabled(working)
            }
        }
        .task { connected = try? await client.connectedDiscord() }
        .alert(ConnectDiscordCopy.failedTitle,
               isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(error ?? "")
        }
    }

    private func connect() async {
        working = true
        defer { working = false }
        do {
            let connection = try await client.discordConnection(app: app)
            let callback = try await webAuthenticationSession.authenticate(
                using: connection.authorizeURL, callbackURLScheme: DiscordConnection.callbackScheme,
                preferredBrowserSession: .shared)
            guard try await client.connectDiscord(callbackURL: callback, connection: connection, device: device) != nil
            else { return }
            let now = try await client.connectedDiscord() ?? ConnectedDiscord(username: nil)
            connected = now
            await onConnected(now)
        } catch ASWebAuthenticationSessionError.canceledLogin {
            return
        } catch {
            self.error = error.localizedDescription
        }
    }
}

/// The words around connecting Discord, shared with Android so both apps say the same thing.
public enum ConnectDiscordCopy {
    public static let connect = "Connect Discord"
    public static let connectedLabel = "Discord"
    public static let connected = "Connected"
    public static let failedTitle = "Couldn't connect Discord"
    public static let explanation = "Connect your Discord account to see the community's Discord channels here as "
        + "yourself. We only learn your Discord name; nothing is posted for you."
}
#endif
