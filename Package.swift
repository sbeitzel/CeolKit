// swift-tools-version: 6.3

import PackageDescription

let package = Package(
  name: "CeolKit",
  platforms: [
    .macOS(.v14),
  ],
  products: [
    .library(name: "CeolKitModel", targets: ["CeolKitModel"]),
    .library(name: "CeolKitParser", targets: ["CeolKitParser"]),
    .library(name: "CeolKitRenderer", targets: ["CeolKitRenderer"]),
  ],
  targets: [
    .target(name: "CeolKitModel"),
    .target(
      name: "CeolKitParser",
      dependencies: ["CeolKitModel"]
    ),
    .target(
      name: "CeolKitRenderer",
      dependencies: ["CeolKitModel"]
    ),
    .testTarget(
      name: "CeolKitParserTests",
      dependencies: ["CeolKitParser"]
    ),
  ],
  swiftLanguageModes: [.v6]
)
