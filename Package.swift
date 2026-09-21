// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "MacSwitch",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "MacSwitch", targets: ["MacSwitch"]),
        .executable(name: "MacSwitchSleepHelper", targets: ["MacSwitchSleepHelper"])
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.9.6")
    ],
    targets: [
        .target(name: "SleepHelperCore", path: "Sources/SleepHelperCore", linkerSettings: [.linkedFramework("Security")]),
        .executableTarget(name: "MacSwitchSleepHelper", dependencies: ["SleepHelperCore"], path: "Sources/MacSwitchSleepHelper"),
        .target(
            name: "CSystemNotify",
            path: "Sources/CSystemNotify",
            publicHeadersPath: "include"
        ),
        .executableTarget(
            name: "MacSwitch",
            dependencies: [
                "CSystemNotify",
                "SleepHelperCore",
                .product(name: "Sparkle", package: "Sparkle")
            ],
            path: "Sources/MacSwitch",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("SwiftUI"),
                .linkedFramework("IOKit"),
                .linkedFramework("ApplicationServices"),
                .linkedFramework("Carbon"),
                .linkedFramework("CoreBluetooth"),
                .linkedFramework("CoreAudio"),
                .linkedFramework("CoreGraphics"),
                .linkedFramework("CoreLocation"),
                .linkedFramework("IOBluetooth"),
                .linkedFramework("ServiceManagement")
            ]
        ),
        .testTarget(
            name: "MacSwitchTests",
            dependencies: ["MacSwitch", "SleepHelperCore"],
            path: "Tests/MacSwitchTests"
        )
    ],
    swiftLanguageModes: [.v6]
)
