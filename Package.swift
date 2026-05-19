// swift-tools-version: 6.3

import PackageDescription

let package = Package(
  name: "ABCKit",
  platforms: [
    .macOS(.v14),
  ],
  products: [
    .library(name: "ABCKitModel", targets: ["ABCKitModel"]),
    .library(name: "ABCKitParser", targets: ["ABCKitParser"]),
    .library(name: "ABCKitRenderer", targets: ["ABCKitRenderer"]),
  ],
  targets: [
    .target(name: "ABCKitModel"),
    .target(
      name: "ABCKitParser",
      dependencies: ["ABCKitModel"]
    ),
    .target(
      name: "ABCKitRenderer",
      dependencies: ["ABCKitModel"]
    ),
    .testTarget(
      name: "ABCKitParserTests",
      dependencies: ["ABCKitParser"]
    ),
  ],
  swiftLanguageModes: [.v6]
)
