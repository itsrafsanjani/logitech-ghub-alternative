// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "G402DPIController",
    platforms: [
        .macOS(.v15)
    ],
    targets: [
        .executableTarget(
            name: "G402DPIController",
            path: "G402DPIController",
            exclude: ["App/Info.plist"],
            swiftSettings: [
                .swiftLanguageMode(.v5),
            ],
            linkerSettings: [
                .linkedFramework("IOKit"),
                .linkedFramework("AppKit"),
                .linkedFramework("ServiceManagement"),
            ]
        ),
        .executableTarget(
            name: "CLISmokeTest",
            path: "CLISmokeTest",
            swiftSettings: [
                .swiftLanguageMode(.v5),
            ],
            linkerSettings: [
                .linkedFramework("IOKit"),
            ]
        ),
    ]
)
