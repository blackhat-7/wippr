// swift-tools-version:5.9
// whisper.cpp's prebuilt xcframework (module `whisper`, C API in whisper.h), for command mode's CPU transcription.
import PackageDescription

let package = Package(
    name: "Whisper",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [.library(name: "whisper", targets: ["whisper"])],
    targets: [
        .binaryTarget(
            name: "whisper",
            url: "https://github.com/ggml-org/whisper.cpp/releases/download/b5130/whisper-b5130-xcframework.zip",
            checksum: "033a43b0174e8cf9b366f72e4a428cdcf126f93ad1c87d3fa119a96bed6f231a"
        ),
    ]
)
