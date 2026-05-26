// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "DrPaste",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .executableTarget(
            name: "DrPaste",
            path: "Sources/DrPaste",
            resources: [
                .process("Resources")
            ]
        )
    ]
)
