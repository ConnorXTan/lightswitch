// swift-tools-version:5.9
// Lightswitch — the notch as a status light for Claude Code sessions, and the
// ambient light sensor as a button.
//
//   swift build            debug binary in .build/debug/Lightswitch
//   swift test             the Swift unit tests (the C suite is `make test`)
//   make app               release build wrapped as build/Lightswitch.app
//   open Package.swift     the same targets inside Xcode
//
// Layout: the existing C engine (src/, include/) is exposed to Swift as the
// CLightswitch module, untouched. LightswitchKit holds everything testable
// without a window; the Lightswitch executable is the AppKit/SwiftUI shell.
import PackageDescription

let package = Package(
    name: "Lightswitch",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Lightswitch", targets: ["Lightswitch"]),
        .library(name: "LightswitchKit", targets: ["LightswitchKit"]),
    ],
    targets: [
        // The C engine. Only the pieces the app needs are compiled; main.c,
        // the terminal UI and the CLI glow overlay stay with the Makefile.
        .target(
            name: "CLightswitch",
            path: ".",
            exclude: [
                "Lightswitch", "tests", "tools", "docs", "examples", "hooks",
                "build", "Makefile", "README.md", "PLAN.md", "PRODUCT.md",
                "LICENSE", ".github",
                "src/main.c", "src/ui.c", "src/glow.c", "src/overlay_macos.m",
            ],
            sources: [
                "src/detector.c", "src/sensor.c", "src/sensor_iokit.c",
                "src/sensor_replay.c", "src/trace.c", "src/config.c",
                "src/action.c", "src/mediakey_macos.m",
            ],
            publicHeadersPath: "include",
            cSettings: [
                .define("LS_HAVE_IOKIT", to: "1"),
            ],
            linkerSettings: [
                .linkedFramework("CoreFoundation"),
                .linkedFramework("IOKit"),
                .linkedFramework("ApplicationServices"),
                .linkedFramework("AppKit"),
            ]
        ),
        .target(
            name: "LightswitchKit",
            dependencies: ["CLightswitch"],
            path: "Lightswitch/Kit"
        ),
        .executableTarget(
            name: "Lightswitch",
            dependencies: ["LightswitchKit"],
            path: "Lightswitch/App"
        ),
        .testTarget(
            name: "LightswitchTests",
            dependencies: ["LightswitchKit"],
            path: "Lightswitch/Tests"
        ),
    ],
    swiftLanguageVersions: [.v5]
)
