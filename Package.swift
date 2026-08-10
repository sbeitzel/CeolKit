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
    // Exported reluctantly.  The intent was to keep this internal to the package, but
    // Tuist (4.202.6) refuses to load a graph in which any target references a library
    // target that has no product — including from a target it is itself ignoring, such
    // as `ckprobe`.  Generation fails with "Couldn't find target 'CeolKitSVGGeometry'".
    // A product-less *executable* target is fine, so `ckprobe` stays unexported.
    .library(name: "CeolKitSVGGeometry", targets: ["CeolKitSVGGeometry"]),
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
    // Development tooling.  `ckprobe` is deliberately not a product: consumers of the
    // package never see it, and `swift run ckprobe` still works because SwiftPM
    // synthesises the product for executable targets in the root package.
    // `CeolKitSVGGeometry` had to be exported — see the note on its product above.
    .target(name: "CeolKitSVGGeometry"),
    .executableTarget(
      name: "ckprobe",
      dependencies: [
        "CeolKitParser",
        "CeolKitSVGRenderer",
        "CeolKitSVGGeometry",
      ]
    ),
    .testTarget(
      name: "CeolKitParserTests",
      dependencies: ["CeolKitParser"]
    ),
    .testTarget(
      name: "CeolKitSVGGeometryTests",
      dependencies: ["CeolKitSVGGeometry"]
    ),
    .testTarget(
      name: "CeolKitSVGRendererTests",
      dependencies: [
        "CeolKitParser",
        "CeolKitSVGRenderer",
        "CeolKitSVGGeometry",
        .product(name: "SnapshotTesting", package: "swift-snapshot-testing"),
      ],
      resources: [
        .process("tunebook.abc"),
        .process("__Snapshots__"),
        // SMuFL's published glyph-name table, the oracle for `SMuFLGlyphConformanceTests`.
        // See Resources/glyphnames-PROVENANCE.txt.
        .process("Resources")
      ]
    ),
  ],
  swiftLanguageModes: [.v6]
)
