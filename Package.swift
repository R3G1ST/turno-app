// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Turno",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Turno",
            path: "Sources/Turno",
            exclude: ["Assets.xcassets"]   // iOS-каталог иконок, мак использует .icns
        )
    ]
)
