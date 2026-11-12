// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Odak",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Odak", targets: ["Odak"]),
    ],
    targets: [
        .target(name: "OdakCore"),
        .executableTarget(name: "Odak", dependencies: ["OdakCore"]),
        .testTarget(name: "OdakCoreTests", dependencies: ["OdakCore"]),
    ]
)
