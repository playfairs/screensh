// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "screensh",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "screensh", targets: ["screensh"])
    ],
    targets: [
        .executableTarget(
            name: "screensh",
            path: "Sources/screensh"
        )
    ]
)
