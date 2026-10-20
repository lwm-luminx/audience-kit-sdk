// swift-tools-version: 6.0
// The member-facing AudienceKit Swift SDK: what an audience's own app (Hot Mess)
// builds on. The staff-side management modules are not part of this package.
// Swift Package Manager only reads a manifest at the repository root, so this one sits beside
// kotlin/ and points into swift/; the Kotlin SDK is the Gradle build in kotlin/.
import PackageDescription

let package = Package(
    name: "AudienceKit",
    platforms: [
        .iOS(.v16),
        .macOS(.v13),
    ],
    products: [
        .library(name: "AudienceCore", targets: ["AudienceCore"]),
        .library(name: "AudienceKit", targets: ["AudienceKit"]),
        .library(name: "AudienceKitUI", targets: ["AudienceKitUI"]),
    ],
    targets: [
        .target(name: "AudienceCore", path: "swift/Sources/AudienceCore"),
        .target(name: "AudienceKit", dependencies: ["AudienceCore"], path: "swift/Sources/AudienceKit"),
        .target(name: "AudienceKitUI", dependencies: ["AudienceCore", "AudienceKit"], path: "swift/Sources/AudienceKitUI"),
        .testTarget(name: "AudienceKitTests", dependencies: ["AudienceKit", "AudienceCore", "AudienceKitUI"],
                    path: "swift/Tests/AudienceKitTests"),
    ]
)
