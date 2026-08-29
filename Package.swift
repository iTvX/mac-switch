// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "MacSwitch",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "MacSwitch", targets: ["MacSwitch"])
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.9.3")
    ],
    targets: [
        .target(
            name: "CSystemNotify",
            path: "Sources/CSystemNotify",
            publicHeadersPath: "include"
        ),
        .executableTarget(
            name: "MacSwitch",
            dependencies: [
                "CSystemNotify",
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
            dependencies: ["MacSwitch"],
            path: "Tests/MacSwitchTests"
        )
    ],
    swiftLanguageModes: [.v6]
)
