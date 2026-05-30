// swift-tools-version: 6.2

import PackageDescription
import CompilerPluginSupport

let package = Package(
    name: "swift-asm-macro",
    platforms: [
        .macOS(.v13),
        .iOS(.v16),
        .tvOS(.v16),
        .watchOS(.v9),
        .macCatalyst(.v16)
    ],
    products: [
        .library(
            name: "AsmMacro",
            targets: ["AsmMacro"]
        ),
        .executable(
            name: "AsmMacroClient",
            targets: ["AsmMacroClient"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-syntax.git", from: "603.0.0-latest"),
        .package(url: "https://github.com/swiftbin/swift-assembler.git", branch: "main"),
    ],
    targets: [
        .macro(
            name: "AsmMacroMacros",
            dependencies: [
                .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
                .product(name: "SwiftCompilerPlugin", package: "swift-syntax"),
                .product(name: "Assembler", package: "swift-assembler"),
            ]
        ),
        .target(name: "AsmMacro", dependencies: ["AsmMacroMacros"]),
        .executableTarget(
            name: "AsmMacroClient",
            dependencies: ["AsmMacro"]
        ),
        .testTarget(
            name: "AsmMacroTests",
            dependencies: [
                "AsmMacroMacros",
                .product(name: "SwiftSyntaxMacrosTestSupport", package: "swift-syntax"),
            ]
        ),
    ]
)
