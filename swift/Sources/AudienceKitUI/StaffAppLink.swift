#if canImport(SwiftUI)
import AudienceKit
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

extension StaffApp {
    /// Whether this phone has the app. Needs each app's ``StaffApp/urlScheme`` under `LSApplicationQueriesSchemes` in
    /// the Info.plist; without it, and off iOS, this is false. Nothing about it leaves the phone.
    @MainActor public var isInstalled: Bool {
        #if canImport(UIKit) && !os(watchOS)
        UIApplication.shared.canOpenURL(homeURL)
        #else
        false
        #endif
    }
}

/// "Open in Velvet" on a venue the signed-in person manages, "Open in Backstage" on their person page: opens the
/// staff app on that page when it's installed, and its download page ("Get Velvet", "Join the Velvet beta") when it
/// isn't.
///
/// ```swift
/// StaffAppLink(.velvet, url: StaffApp.velvet(venueID: venue.id, audienceID: audience.id))
/// ```
public struct StaffAppLink<Label: View>: View {
    private let app: StaffApp
    private let url: URL
    private let label: (_ title: String, _ systemImage: String) -> Label
    @Environment(\.openURL) private var openURL
    @State private var installed = true

    /// - Parameters:
    ///   - url: where in the app to open, e.g. ``StaffApp/velvet(venueID:audienceID:)``; the app's home by default.
    ///   - label: draws the button from its title ("Open in Velvet" or "Get Velvet") and SF Symbol.
    public init(_ app: StaffApp, url: URL? = nil,
                @ViewBuilder label: @escaping (_ title: String, _ systemImage: String) -> Label) {
        self.app = app
        self.url = url ?? app.homeURL
        self.label = label
    }

    public var body: some View {
        Button {
            openURL(installed ? url : app.downloadURL(campaign: "open_in_staff_app")) { opened in
                if !opened { openURL(app.downloadURL(campaign: "open_in_staff_app")) }
            }
        } label: {
            label(app.linkTitle(installed: installed), app.systemImage)
        }
        .onAppear { installed = app.isInstalled }
        .accessibilityIdentifier("staffAppLink.\(app.rawValue)")
    }
}

extension StaffAppLink where Label == SwiftUI.Label<Text, Image> {
    /// The plain button: its title with the app's symbol.
    public init(_ app: StaffApp, url: URL? = nil) {
        self.init(app, url: url) { title, systemImage in SwiftUI.Label(title, systemImage: systemImage) }
    }
}
#endif
