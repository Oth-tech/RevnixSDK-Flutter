// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "revnix_flutter",
    // revnix-swift's floor; the podspec says the same.
    platforms: [
        .iOS("16.0")
    ],
    products: [
        .library(name: "revnix-flutter", targets: ["revnix_flutter"])
    ],
    dependencies: [
        .package(name: "FlutterFramework", path: "../FlutterFramework"),
        // The git submodule at ios/revnix_flutter/Revnix (revnix-swift). It
        // sits INSIDE this package on purpose: Flutter's SwiftPM integration
        // symlinks the package directory, so a path outside it would not
        // resolve. Under CocoaPods the same sources compile into this module
        // instead (see the podspec).
        .package(name: "Revnix", path: "Revnix"),
    ],
    targets: [
        .target(
            name: "revnix_flutter",
            dependencies: [
                .product(name: "FlutterFramework", package: "FlutterFramework"),
                .product(name: "Revnix", package: "Revnix"),
            ]
        )
    ]
)
