// swift-tools-version: 6.0

import Foundation
import PackageDescription

// アクティブな developer directory を xcode-select のシンボリックリンクから判定する。
// Xcode のない環境（CommandLineTools のみ）では `swift test` が swift-testing の
// テストを発見できないため、CLT の Testing.framework を直接リンクした実行ターゲット
// （`swift run TsuraraTests` / Scripts/test.sh）でテストを実行する。
// Xcode がある環境では通常の testTarget を宣言し、`swift test` がそのまま使える。
let developerDir =
    (try? FileManager.default.destinationOfSymbolicLink(atPath: "/var/db/xcode_select_link"))
    ?? "/Library/Developer/CommandLineTools"
let isCommandLineToolsOnly = developerDir.hasSuffix("CommandLineTools")

let cltFrameworksDir = "/Library/Developer/CommandLineTools/Library/Developer/Frameworks"

let testTarget: Target =
    isCommandLineToolsOnly
    ? .executableTarget(
        name: "TsuraraTests",
        dependencies: ["TsuraraCore"],
        path: "Tests/TsuraraCoreTests",
        swiftSettings: [
            .unsafeFlags(["-F", cltFrameworksDir]),
        ],
        linkerSettings: [
            .unsafeFlags([
                "-F", cltFrameworksDir,
                "-framework", "Testing",
                "-Xlinker", "-rpath",
                "-Xlinker", cltFrameworksDir,
                "-Xlinker", "-rpath",
                "-Xlinker", "/Library/Developer/CommandLineTools/Library/Developer/usr/lib",
            ]),
        ]
    )
    : .testTarget(
        name: "TsuraraCoreTests",
        dependencies: ["TsuraraCore"],
        path: "Tests/TsuraraCoreTests",
        exclude: ["TestRunner.swift"]
    )

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
        testTarget,
    ]
)
