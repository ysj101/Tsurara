// swift-tools-version: 6.0

import Foundation
import PackageDescription

// Xcode の有無でテストターゲットの宣言を切り替える（背景は README の Test 節を参照）。
// 判定は Scripts/test.sh と同一: DEVELOPER_DIR 環境変数 → xcode-select の実体リンクの順。
let developerDir =
    ProcessInfo.processInfo.environment["DEVELOPER_DIR"]
    ?? (try? FileManager.default.destinationOfSymbolicLink(atPath: "/var/db/xcode_select_link"))
    ?? "/Library/Developer/CommandLineTools"
let isCommandLineToolsOnly = developerDir.hasSuffix("CommandLineTools")

let cltFrameworksDir = "\(developerDir)/Library/Developer/Frameworks"
let cltTestingLibDir = "\(developerDir)/Library/Developer/usr/lib"

let testTarget: Target =
    isCommandLineToolsOnly
    ? .executableTarget(
        name: "TsuraraCoreTests",
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
                "-Xlinker", cltTestingLibDir,
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
