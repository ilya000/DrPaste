// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "DrPaste",
    platforms: [
        .macOS(.v13)
    ],
    dependencies: [
        // Shared Latin ↔ Cyrillic transliteration engine (14 langs + detection), extracted from
        // this app so DrPaste and PolyType share ONE source of truth (sibling checkout).
        .package(path: "../ioTranslit"),
    ],
    targets: [
        .executableTarget(
            name: "DrPaste",
            dependencies: [
                .product(name: "ioTranslit", package: "ioTranslit"),
            ],
            path: "Sources/DrPaste",
            resources: [
                .process("Resources")
            ]
        ),
        .testTarget(
            name: "DrPasteTests",
            dependencies: ["DrPaste"],
            path: "Tests/DrPasteTests"
        )
    ]
)
