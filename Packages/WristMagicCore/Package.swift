// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "WristMagicCore",
    platforms: [.iOS(.v17), .watchOS(.v10)],
    products: [.library(name: "WristMagicCore", targets: ["WristMagicCore"])],
    targets: [.target(name: "WristMagicCore"), .testTarget(name: "WristMagicCoreTests", dependencies: ["WristMagicCore"])],
    swiftLanguageModes: [.v6]
)
