// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "MidiPassthrough",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(name: "MidiPassthrough", path: "Sources/MidiPassthrough")
    ]
)
