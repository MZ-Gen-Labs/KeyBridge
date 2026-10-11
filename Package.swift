// swift-tools-version: 5.10
import PackageDescription
let package = Package(name: "KeyBridge", platforms: [.macOS(.v14)], products: [.executable(name: "KeyBridge", targets: ["KeyBridge"])], targets: [.executableTarget(name: "KeyBridge"), .testTarget(name: "KeyBridgeTests", dependencies: ["KeyBridge"])])
