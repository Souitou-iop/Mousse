// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Mousse",
    defaultLocalization: "en",
    platforms: [.macOS("15.0")],
    targets: [
        .executableTarget(
            name: "Mousse",
            dependencies: ["MousseHIDBridge"],
            path: "Sources/Mousse",
            resources: [.process("Resources")],
            swiftSettings: [
                // v1 uses Swift 5 language mode: the CGEventTap C-callback bridging is simpler
                // without Swift 6 strict-concurrency ceremony. Tighten to .v6 once the engine is stable.
                .swiftLanguageMode(.v5)
            ]
        ),
        .target(
            name: "MousseHIDBridge",
            path: "Sources/MousseHIDBridge",
            publicHeadersPath: "include",
            linkerSettings: [.linkedFramework("IOKit")]
        ),
        .testTarget(
            name: "MousseTests",
            dependencies: ["Mousse"],
            path: "Tests/MousseTests",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
