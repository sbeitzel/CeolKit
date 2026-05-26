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
    .library(name: "CeolKitSVGRenderer", targets: ["CeolKitSVGRenderer"]),
  ],
  dependencies: [
    .package(url: "https://github.com/pointfreeco/swift-snapshot-testing", from: "1.17.0"),
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
    .target(
      name: "CeolKitSVGRenderer",
      dependencies: ["CeolKitRenderer"],
      resources: [.process("Resources")]
    ),
    .testTarget(
      name: "CeolKitParserTests",
      dependencies: ["CeolKitParser"]
    ),
    .testTarget(
      name: "CeolKitSVGRendererTests",
      dependencies: [
        "CeolKitSVGRenderer",
        .product(name: "SnapshotTesting", package: "swift-snapshot-testing"),
      ]
    ),
  ],
  swiftLanguageModes: [.v6]
)
