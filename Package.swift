// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "CHMReader",
    defaultLocalization: "zh-Hant",
    platforms: [.macOS(.v14)],
    targets: [
        .target(
            name: "CCHMLib",
            exclude: ["COPYING", "AUTHORS"],
            cSettings: [
                .define("CHM_MT"),
                .define("CHM_USE_PREAD"),
                .unsafeFlags(["-w"]),
            ]
        ),
        .target(
            name: "CHMKit",
            dependencies: ["CCHMLib"]
        ),
        .executableTarget(
            name: "CHMReader",
            dependencies: ["CHMKit"]
        ),
        .testTarget(
            name: "CHMKitTests",
            dependencies: ["CHMKit"]
        ),
    ],
    swiftLanguageModes: [.v5]
)
