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
        // Test target temporarily disabled — requires full Xcode.app for XCTest
        // module (Command Line Tools alone don't ship it reliably). Tests live
        // in Tests/DrPasteTests/ and are ready to run on any machine with
        // Xcode installed; re-enable this section when iterating on tests:
        //
        // ,.testTarget(
        //     name: "DrPasteTests",
        //     dependencies: ["DrPaste"],
        //     path: "Tests/DrPasteTests"
        // )
    ]
)
