// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "AutoTranslateKit",
    platforms: [
        .iOS("18.0"),
        .macOS("15.0")
    ],
    products: [
        .library(name: "AutoTranslateKit", targets: ["AutoTranslateKit"]),
        .plugin(name: "AutoTranslateGuard", targets: ["AutoTranslateGuardPlugin"]),
        .plugin(name: "AutoTranslateGuardCommand", targets: ["AutoTranslateGuardCommandPlugin"])
    ],
    dependencies: [
        .package(
            url: "https://github.com/swiftlang/swift-syntax.git",
            exact: "509.1.1"
        )
    ],
    targets: [
        .target(name: "AutoTranslateKit"),
        .target(
            name: "AutoTranslateGuardCore",
            dependencies: [
                .product(name: "SwiftParser", package: "swift-syntax"),
                .product(name: "SwiftSyntax", package: "swift-syntax")
            ]
        ),
        .executableTarget(
            name: "AutoTranslateGuardScanner",
            dependencies: ["AutoTranslateGuardCore"]
        ),
        .plugin(
            name: "AutoTranslateGuardPlugin",
            capability: .buildTool(),
            dependencies: ["AutoTranslateGuardScanner"]
        ),
        .plugin(
            name: "AutoTranslateGuardCommandPlugin",
            capability: .command(
                intent: .custom(
                    verb: "autotranslate-guard",
                    description: "Audit or safely fix raw dynamic display strings"
                ),
                permissions: [
                    .writeToPackageDirectory(reason: "Apply explicitly requested --fix rewrites")
                ]
            ),
            dependencies: ["AutoTranslateGuardScanner"]
        ),
        .testTarget(
            name: "AutoTranslateKitTests",
            dependencies: ["AutoTranslateKit"]
        ),
        .testTarget(
            name: "AutoTranslateGuardCoreTests",
            dependencies: ["AutoTranslateGuardCore"]
        )
    ]
)
