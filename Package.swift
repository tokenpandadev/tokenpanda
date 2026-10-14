// SPDX-FileCopyrightText: 2026 tokenpanda
// SPDX-License-Identifier: MIT
// swift-tools-version: 6.0
// tokenpanda: a macOS menu bar app that reads Claude Code's status line feed and the Mac's own figures. MIT licence.
import PackageDescription

let swift6: [SwiftSetting] = [.swiftLanguageMode(.v6)]

let package = Package(
    name: "tokenpanda",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "Text", swiftSettings: swift6),
        .target(name: "Pace", swiftSettings: swift6),
        .target(name: "Prices", swiftSettings: swift6),
        .target(name: "Feed", dependencies: ["Pace"], swiftSettings: swift6),
        .target(name: "Transcripts", dependencies: ["Prices"], swiftSettings: swift6),
        .target(name: "MacStats", swiftSettings: swift6, linkerSettings: [.linkedFramework("IOKit")]),
        .target(name: "UI", dependencies: ["Text", "Pace", "Prices", "Feed", "Transcripts", "MacStats"], swiftSettings: swift6,
                linkerSettings: [.linkedFramework("AppKit")]),
        .executableTarget(name: "tokenpanda", dependencies: ["UI", "Text", "Pace", "Prices", "Feed", "Transcripts", "MacStats"],
                          path: "Sources/App", swiftSettings: swift6,
                          linkerSettings: [.linkedFramework("AppKit"), .linkedFramework("UserNotifications")]),
        .testTarget(name: "tokenpandaTests", dependencies: ["Text", "Pace", "Prices", "Feed", "Transcripts", "MacStats"],
                    resources: [.copy("Fixtures")], swiftSettings: swift6),
    ]
)
