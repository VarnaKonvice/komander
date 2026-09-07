// swift-tools-version: 6.2
import PackageDescription

let package = Package(
  name: "LazenskyCommander",
  // macOS hosts the Swift Testing suite and CoreCheck; no macOS application is shipped.
  // Declare its runtime contract instead of inheriting SwiftPM's legacy default.
  platforms: [.macOS(.v13), .iOS(.v26), .watchOS(.v26)],
  products: [
    .library(name: "LazenskyCommanderCore", targets: ["LazenskyCommanderCore"]),
    .executable(name: "LazenskyCommanderCoreCheck", targets: ["LazenskyCommanderCoreCheck"])
  ],
  targets: [
    .target(name: "LazenskyCommanderCore"),
    .executableTarget(name: "LazenskyCommanderCoreCheck", dependencies: ["LazenskyCommanderCore"]),
    .testTarget(name: "LazenskyCommanderCoreTests", dependencies: ["LazenskyCommanderCore"])
  ]
)
