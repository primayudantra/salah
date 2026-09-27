// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Salah",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "SalahCore", targets: ["SalahCore"]),
        .executable(name: "salah", targets: ["salah"]),
        .executable(name: "SalahMac", targets: ["SalahMac"]),
    ],
    dependencies: [
        // 1.5.0 requires swift-tools 6.0; pinned to 1.4.0 until the toolchain is upgraded.
        .package(url: "https://github.com/batoulapps/adhan-swift", exact: "1.4.0"),
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.3.0"),
    ],
    targets: [
        .target(
            name: "SalahCore",
            dependencies: [.product(name: "Adhan", package: "adhan-swift")]
        ),
        .executableTarget(
            name: "salah",
            dependencies: [
                "SalahCore",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
        .executableTarget(
            name: "SalahMac",
            dependencies: ["SalahCore"],
            path: "App/SalahMac",
            // Resources are copied into Salah.app/Contents/Resources by scripts/build-app.sh.
            exclude: ["Resources", "Info.plist"]
        ),
        .testTarget(
            name: "SalahCoreTests",
            dependencies: ["SalahCore", .product(name: "Adhan", package: "adhan-swift")]
        ),
        .testTarget(name: "SalahCLITests", dependencies: ["salah", "SalahCore"]),
    ]
)
