// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "apptracer_flutter_desktop",
    platforms: [
        .macOS("12.0")
    ],
    products: [
        .library(
            name: "apptracer-flutter-desktop",
            type: .static,
            targets: ["apptracer_flutter_desktop"]
        )
    ],
    dependencies: [
        .package(name: "FlutterFramework", path: "../FlutterFramework"),
        // Must match the Sentry Flutter 10.6.0 binary and native lifecycle.
        .package(
            url: "https://github.com/getsentry/sentry-apple-binaries",
            exact: "9.35.0"
        )
    ],
    targets: [
        .target(
            name: "apptracer_flutter_desktop",
            dependencies: [
                .product(name: "FlutterFramework", package: "FlutterFramework"),
                .product(
                    name: "Sentry-Static",
                    package: "sentry-apple-binaries"
                )
            ]
        )
    ]
)
