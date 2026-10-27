// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "WatchDocsKit",
    platforms: [
        .iOS(.v17),
        .watchOS(.v10),
        .macOS(.v14),
    ],
    products: [
        .library(name: "WatchDocsKit", targets: ["WatchDocsKit"]),
    ],
    targets: [
        .target(
            name: "WatchDocsKit",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "WatchDocsKitTests",
            dependencies: ["WatchDocsKit"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
