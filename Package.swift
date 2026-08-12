// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Tsurara",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .executable(name: "Tsurara", targets: ["Tsurara"]),
        .library(name: "TsuraraCore", targets: ["TsuraraCore"]),
    ],
    targets: [
        .executableTarget(
            name: "Tsurara",
            dependencies: ["TsuraraCore"]
        ),
        .target(name: "TsuraraCore"),
        // NOTE: Xcode のない環境（CommandLineTools のみ）では `swift test` が
        // swift-testing のテストを発見できないため、テストは実行ターゲットとして
        // ビルドし `swift run TsuraraTests`（Scripts/test.sh）で実行する。
        .executableTarget(
            name: "TsuraraTests",
            dependencies: ["TsuraraCore"],
            path: "Tests/TsuraraCoreTests",
            swiftSettings: [
                .unsafeFlags([
                    "-F", "/Library/Developer/CommandLineTools/Library/Developer/Frameworks",
                ]),
            ],
            linkerSettings: [
                .unsafeFlags([
                    "-F", "/Library/Developer/CommandLineTools/Library/Developer/Frameworks",
                    "-framework", "Testing",
                    "-Xlinker", "-rpath",
                    "-Xlinker", "/Library/Developer/CommandLineTools/Library/Developer/Frameworks",
                    "-Xlinker", "-rpath",
                    "-Xlinker", "/Library/Developer/CommandLineTools/Library/Developer/usr/lib",
                ]),
            ]
        ),
    ]
)
