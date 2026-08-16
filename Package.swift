// swift-tools-version: 5.9
import PackageDescription

// LabLLM — native macOS LLM training lab built on Apple's MLX.
//
// This manifest lets you `swift run` a quick build from the terminal, but the
// RECOMMENDED path is an Xcode "macOS App" target (see README.md) so you get a
// real .app bundle, Metal entitlements, and the app menu. Either way the source
// under Sources/LabLLM is identical.
let package = Package(
    name: "LabLLM",
    platforms: [.macOS(.v14)],
    dependencies: [
        // 0.31.x fixes the "std::array ... undefined template" C++ build error seen
        // on newer Xcode/libc++ toolchains (older MLX relied on a transitive <array>
        // include that newer libc++ dropped). Always build with FULL Xcode, not the
        // Command Line Tools — MLX JIT-compiles Metal kernels and needs Xcode's SDK.
        .package(url: "https://github.com/ml-explore/mlx-swift", from: "0.31.6")
    ],
    targets: [
        .executableTarget(
            name: "LabLLM",
            dependencies: [
                .product(name: "MLX", package: "mlx-swift"),
                .product(name: "MLXNN", package: "mlx-swift"),
                .product(name: "MLXOptimizers", package: "mlx-swift"),
                .product(name: "MLXRandom", package: "mlx-swift"),
                .product(name: "MLXFast", package: "mlx-swift"),
            ],
            path: "Sources/LabLLM",
            resources: [
                .copy("Resources/mlx.metallib"),
                .copy("Resources/default.metallib"),
            ]
        ),
        .testTarget(
            name: "LabLLMCoreTests",
            dependencies: [
                "LabLLM",
                .product(name: "MLX", package: "mlx-swift"),
                .product(name: "MLXNN", package: "mlx-swift"),
            ],
            path: "Tests/LabLLMCoreTests"
        )
    ]
)
