// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "browser",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Browser",
            path: "Sources/Browser"
        ),
        .testTarget(
            name: "BrowserTests",
            dependencies: ["Browser"],
            path: "Tests/BrowserTests"
        ),
    ]
)
