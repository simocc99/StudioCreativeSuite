// swift-tools-version: 6.0
import PackageDescription

let modules = [
    "StudioCore", "StudioAssets", "StudioPhoto", "StudioVector", "StudioPaint",
    "StudioVideo", "StudioMotion", "StudioAudio", "StudioLayout", "StudioPDF",
]

let package = Package(
    name: "StudioKit",
    defaultLocalization: "it",
    platforms: [.iOS(.v18)],
    products: [
        .library(name: "StudioKit", targets: modules),
    ],
    targets: [
        // Built by Scripts/build-photo-engine.sh (Rust, LightCraft). Not committed.
        .binaryTarget(name: "StudioPhotoEngineFFI", path: "Frameworks/StudioPhotoEngineFFI.xcframework"),

        .target(name: "StudioCore"),
        .target(name: "StudioAssets", dependencies: ["StudioCore"]),
        .target(
            name: "StudioPhoto",
            dependencies: [
                "StudioCore",
                "StudioPaint",
                "StudioPhotoEngineFFI",
            ],
            linkerSettings: [.linkedFramework("Security"), .linkedFramework("SystemConfiguration")]
        ),
        .target(name: "StudioVector", dependencies: ["StudioCore"]),
        .target(name: "StudioPaint", dependencies: ["StudioCore"]),
        .target(name: "StudioVideo", dependencies: ["StudioCore"]),
        .target(name: "StudioMotion", dependencies: ["StudioCore"]),
        .target(name: "StudioAudio", dependencies: ["StudioCore"]),
        .target(name: "StudioLayout", dependencies: ["StudioCore"]),
        .target(name: "StudioPDF", dependencies: ["StudioCore"]),

        .testTarget(
            name: "StudioKitTests",
            dependencies: modules.map { .target(name: $0) }
        ),
    ],
    swiftLanguageModes: [.v5]
)
