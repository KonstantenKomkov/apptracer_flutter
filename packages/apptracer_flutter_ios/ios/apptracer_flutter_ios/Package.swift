// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

// The Swift Package Manager half of this plugin. The podspec next to this
// directory builds the same sources for applications that stay on CocoaPods;
// both are kept, because Flutter picks whichever the application uses.
//
// OKTracer is declared the way the podspec declares it — by version, from the
// vendor's own repository — so that this package still redistributes nothing.
// The vendor publishes the SDK as binary targets in the same repository that
// serves its CocoaPods specs.
let package = Package(
    name: "apptracer_flutter_ios",
    platforms: [
        // Matches the deployment target of the OKTracer xcframework and the
        // `s.platform` line of the podspec.
        .iOS("13.0")
    ],
    products: [
        // Hyphens, not underscores: Swift Package Manager uses the library name
        // as the CFBundleIdentifier when it links dynamically, and that cannot
        // hold an underscore. Flutter looks the product up under exactly this
        // name, derived from the plugin name.
        //
        // Static, because OKTracer is a static xcframework. This is the same
        // requirement the podspec's `use_frameworks! :linkage => :static` puts
        // on a CocoaPods application, and it keeps a static binary from being
        // wrapped in a dynamic one.
        .library(name: "apptracer-flutter-ios", type: .static, targets: ["apptracer_flutter_ios"])
    ],
    dependencies: [
        // 1.5.2 is the first tag whose binary targets point at
        // nexus-external.vkteam.ru; the manifests at every earlier tag download
        // from artifactory-external.vkpartner.ru, which the vendor shut down
        // on 2026-08-31. With the floor, a Package.resolved that still pins
        // 1.5.1 fails to resolve against a named constraint instead of on a
        // dead download URL.
        .package(url: "https://github.com/odnoklassniki/tracer-ios.git", from: "1.5.2"),
    ],
    targets: [
        .target(
            name: "apptracer_flutter_ios",
            dependencies: [
                // The package identity is the repository name, not the name
                // declared inside the vendor's manifest ("OKTracerPackage").
                .product(name: "OKTracerPackage", package: "tracer-ios"),
            ]
            // No dependency on FlutterFramework, the package Flutter generates
            // for its own framework. `import Flutter` resolves through the
            // framework search paths Flutter passes to the build, so this
            // manifest depends on nothing the SDK generates and therefore
            // resolves on every Flutter that supports Swift Package Manager,
            // not only on those new enough to generate FlutterFramework. This
            // follows url_launcher_ios (flutter/packages) and vkid_flutter_sdk;
            // see docs/design-decisions.md for the trade-off.
        )
    ]
)
