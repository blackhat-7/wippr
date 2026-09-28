// swift-tools-version:5.9
// llama.cpp's prebuilt xcframework (module `llama`, C API in llama.h), for S1-mini cleanup on the CPU.
import PackageDescription

let package = Package(
    name: "Llama",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [.library(name: "llama", targets: ["llama"])],
    targets: [
        .binaryTarget(
            name: "llama",
            url: "https://github.com/ggml-org/llama.cpp/releases/download/b11238/llama-b11238-xcframework.zip",
            checksum: "c5779c8615b78cba5a7b22cd85af84bd7f1c424c48b7778b11ca1124b1c9aac0"
        ),
    ]
)
