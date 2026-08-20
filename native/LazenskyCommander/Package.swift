// swift-tools-version: 6.2
import PackageDescription

let package = Package(
  name: "LazenskyCommander",
  platforms: [.iOS(.v26)],
  products: [
    .library(name: "LazenskyCommanderCore", targets: ["LazenskyCommanderCore"]),
    .executable(name: "LazenskyCommander", targets: ["LazenskyCommanderApp"]),
    .executable(name: "LazenskyCommanderCoreCheck", targets: ["LazenskyCommanderCoreCheck"])
  ],
  targets: [
    .target(name: "LazenskyCommanderCore"),
    .executableTarget(name: "LazenskyCommanderApp", dependencies: ["LazenskyCommanderCore"]),
    .executableTarget(name: "LazenskyCommanderCoreCheck", dependencies: ["LazenskyCommanderCore"]),
    .testTarget(name: "LazenskyCommanderCoreTests", dependencies: ["LazenskyCommanderCore"])
  ]
)
