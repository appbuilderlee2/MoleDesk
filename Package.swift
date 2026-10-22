// swift-tools-version: 5.7
import PackageDescription

let package = Package(name: "MoleDesk", platforms: [.macOS(.v12)], products: [.executable(name: "MoleDesk", targets: ["MoleDesk"])], targets: [.executableTarget(name: "MoleDesk")])
