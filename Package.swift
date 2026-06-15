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
        .executableTarget(
            name: "MacSwitch",
            dependencies: [
                .product(name: "Sparkle", package: "Sparkle")
            ],
            path: "Sources/MacSwitch",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("SwiftUI"),
                .linkedFramework("IOKit"),
                .linkedFramework("ApplicationServices"),
                .linkedFramework("Carbon"),
                .linkedFramework("CoreAudio"),
                .linkedFramework("CoreGraphics"),
                .linkedFramework("CoreLocation"),
                .linkedFramework("IOBluetooth"),
                .linkedFramework("ServiceManagement")
            ]
        ),
        .testTarget(
            name: "MacSwitchTests",
            path: "Tests/MacSwitchTests"
        )
    ],
    swiftLanguageModes: [.v5]
)
