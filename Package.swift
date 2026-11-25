// swift-tools-version: 6.0
// The AudienceKit Swift SDK: the member-facing modules an audience's own app (Hot Mess) builds on, and StaffKit's API
// modules (the staff session and the staff API clients) that the staff apps build on. StaffKit's SwiftUI modules ship
// only as binaries, from lwm-luminx/staff-kit-binaries.
// Swift Package Manager only reads a manifest at the repository root, so this one sits beside
// core/ (Kotlin Multiplatform) and android/ and points into swift/.
import PackageDescription

let package = Package(
    name: "AudienceKit",
    platforms: [
        .iOS(.v16),
        .macOS(.v13),
        // Apple TV builds the core and the shared look only (Velvet on Apple TV): AudienceKitUI's screens are left out there.
        .tvOS(.v17),
    ],
    products: [
        .library(name: "AudienceCore", targets: ["AudienceCore"]),
        .library(name: "AudienceKit", targets: ["AudienceKit"]),
        .library(name: "AudienceKitUI", targets: ["AudienceKitUI"]),
        // For apps' unit tests: a stub GraphQL API (GraphQLStub) that enforces the complexity budget.
        .library(name: "AudienceKitTesting", targets: ["AudienceKitTesting"]),
        // StaffKit's API side: the staff session (platform sign-in, the chosen audience, the staff cable) and the
        // staffql clients, feeds and models. Foundation only, so they build everywhere AudienceCore does.
        .library(name: "StaffKitCore", targets: ["StaffKitCore"]),
        .library(name: "StaffKitServices", targets: ["StaffKitServices"]),
        // Arbiter's engine-facing types and protocols, and what a client (StaffKit's `arbiterctl`) and a running Mac
        // Arbiter say over its control socket.
        .library(name: "ArbiterModels", targets: ["ArbiterModels"]),
        .library(name: "ArbiterControl", targets: ["ArbiterControl"]),
    ],
    targets: [
        .target(name: "AudienceCore", path: "swift/Sources/AudienceCore"),
        .target(name: "AudienceKit", dependencies: ["AudienceCore"], path: "swift/Sources/AudienceKit"),
        .target(name: "AudienceKitUI", dependencies: ["AudienceCore", "AudienceKit"], path: "swift/Sources/AudienceKitUI"),
        .target(name: "AudienceKitTesting", dependencies: ["AudienceCore"], path: "swift/Sources/AudienceKitTesting"),
        .target(name: "StaffKitCore", dependencies: ["AudienceCore"], path: "swift/Sources/StaffKitCore"),
        .target(name: "ArbiterModels", path: "swift/Sources/ArbiterModels"),
        .target(name: "StaffKitServices", dependencies: ["StaffKitCore", "ArbiterModels"], path: "swift/Sources/StaffKitServices"),
        .target(name: "ArbiterControl", path: "swift/Sources/ArbiterControl"),
        .testTarget(name: "StaffKitTests", dependencies: ["AudienceCore", "AudienceKit", "StaffKitCore", "StaffKitServices", "ArbiterModels"],
                    path: "swift/Tests/StaffKitTests"),
        .testTarget(name: "ArbiterModelsTests", dependencies: ["ArbiterModels"], path: "swift/Tests/ArbiterModelsTests"),
        .testTarget(name: "ArbiterControlTests", dependencies: ["ArbiterControl"], path: "swift/Tests/ArbiterControlTests"),
        .testTarget(name: "AudienceKitTests", dependencies: ["AudienceKit", "AudienceCore", "AudienceKitUI", "AudienceKitTesting"],
                    path: "swift/Tests/AudienceKitTests"),
    ]
)
