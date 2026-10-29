// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "Antille",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "Antille", targets: ["Antille"]),
        .executable(name: "AntilleApp", targets: ["AntilleApp"]),
        .executable(name: "antille", targets: ["AntilleCLI"])
    ],
    targets: [
        .target(name: "Antille"),
        .executableTarget(name: "AntilleApp", dependencies: ["Antille"]),
        .executableTarget(name: "AntilleCLI", dependencies: ["Antille"]),
        .executableTarget(name: "AntilleChecks", dependencies: ["Antille"], path: "Tests/AntilleChecks")
    ]
)
