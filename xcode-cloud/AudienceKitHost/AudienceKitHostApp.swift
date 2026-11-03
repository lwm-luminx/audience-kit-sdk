// Xcode Cloud can't build a standalone Swift package, only an app project that uses it as a local package
// (developer.apple.com/documentation/xcode/building-swift-packages-or-swift-playground-app-projects-with-xcode-cloud).
// This app is that project: it links every library the SDK ships so the SDK Xcode Cloud workflow builds all three for
// iOS, and the SDK scheme runs the package's own tests. It is never archived or distributed.
import AudienceCore
import AudienceKit
import AudienceKitUI
import SwiftUI

@main
struct AudienceKitHostApp: App {
    var body: some Scene {
        WindowGroup {
            Text("AudienceKit \(AudienceKitSDK.version)")
        }
    }
}
