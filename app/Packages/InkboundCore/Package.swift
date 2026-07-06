// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "InkboundCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "InkCore", targets: ["InkCore"]),
        .library(name: "InkData", targets: ["InkData"]),
        .library(name: "InkNet", targets: ["InkNet"]),
        .library(name: "InkRender", targets: ["InkRender"]),
        .library(name: "InkMoney", targets: ["InkMoney"]),
        .library(name: "InkSafety", targets: ["InkSafety"]),
        .library(name: "InkAnalytics", targets: ["InkAnalytics"]),
    ],
    targets: [
        // Domain types, idle-send FSM, snapshot planning, reply assembly. Foundation/CoreGraphics only.
        .target(name: "InkCore"),
        .target(name: "InkData", dependencies: ["InkCore"]),
        .target(name: "InkNet", dependencies: ["InkCore"]),
        .target(name: "InkRender", dependencies: ["InkCore"]),
        .target(name: "InkMoney", dependencies: ["InkCore"]),
        .target(name: "InkSafety", dependencies: ["InkCore", "InkNet"]),
        .target(name: "InkAnalytics", dependencies: ["InkCore"]),

        .testTarget(name: "InkCoreTests", dependencies: ["InkCore"]),
        .testTarget(name: "InkDataTests", dependencies: ["InkData"]),
        .testTarget(name: "InkNetTests", dependencies: ["InkNet"]),
        .testTarget(name: "InkRenderTests", dependencies: ["InkRender"]),
        .testTarget(name: "InkMoneyTests", dependencies: ["InkMoney"]),
        .testTarget(name: "InkSafetyTests", dependencies: ["InkSafety"]),
        .testTarget(name: "InkAnalyticsTests", dependencies: ["InkAnalytics"]),
    ]
)
