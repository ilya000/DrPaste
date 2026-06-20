// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "DrPaste",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .target(
            name: "ioTranslit",
            path: "Sources/ioTranslit"
        ),
        .executableTarget(
            name: "DrPaste",
            dependencies: [
                "ioTranslit",
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
