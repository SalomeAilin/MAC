// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "SelectTranslate",
    platforms: [.macOS(.v26)],
    targets: [
        .executableTarget(
            name: "SelectTranslate",
            swiftSettings: [
                // AppKit / SwiftUI 应用：默认所有代码都在主线程，后台工作显式标注 nonisolated
                .defaultIsolation(MainActor.self),
            ]
        ),
    ]
)
