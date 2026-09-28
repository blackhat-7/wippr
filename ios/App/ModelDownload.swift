import Foundation

/// A model the app downloads on request. Home's menus list it as "Name (download · size)"; picking it starts the
/// download, and a progress line shows under the menu until it's done.
@MainActor
protocol DownloadableModel: AnyObject {
    var isInstalled: Bool { get }
    /// 0…1 while downloading.
    var downloadProgress: Double? { get }
    var downloadError: String? { get }
    var downloadSize: Int64 { get }
    func startDownload()
}

/// Where an experimental model's Core AI bundle is hosted: our converted copies on Hugging Face, pinned to a
/// revision (licences and attribution in each repo's model card). The app downloads them on request (Home →
/// Experimental), since they're too big to ship inside it.
struct ModelSource: Sendable {
    let name: String
    let repo: String
    let revision: String
    /// Paths inside the repo (and inside the bundle folder), with sizes in bytes.
    let files: [(path: String, size: Int64)]

    var size: Int64 { files.reduce(0) { $0 + $1.size } }

    /// "S1-mini" by "Superwhisper" (Apache-2.0 + naming term), 8-bit.
    static let s1mini = ModelSource(
        name: "S1-mini", repo: "satuke/s1-mini-coreai-ios", revision: "4a4269122b22f7469c6775a41893c9e63d230d2f",
        files: [
            ("metadata.json", 575),
            ("s1-mini-ios-8bit.aimodel/main.hash", 32),
            ("s1-mini-ios-8bit.aimodel/main.mlirb", 634_810_547),
            ("s1-mini-ios-8bit.aimodel/metadata.json", 105),
            ("tokenizer/chat_template.jinja", 4173),
            ("tokenizer/tokenizer.json", 11_422_650),
            ("tokenizer/tokenizer_config.json", 694),
        ])

    /// The same S1-mini as a 4-bit GGUF for llama.cpp on the CPU (`CPUCleaner`), from Superwhisper's own repo.
    static let s1miniGGUF = ModelSource(
        name: "S1-mini (CPU)", repo: "superwhisper/s1-mini-GGUF", revision: "34add00a48a2e5d24e5a4ee5405a99620a3a240c",
        files: [("s1-mini-q4_k_m.gguf", 484_219_808)])
    /// NVIDIA Parakeet TDT 0.6B v2 (CC BY 4.0), streaming float16.
    static let parakeet = ModelSource(
        name: "Parakeet", repo: "satuke/parakeet-tdt-0.6b-v2-coreai-ios", revision: "b879351a2c9f52e5948114d54f9d50b228b5dd4a",
        files: [
            ("metadata.json", 937),
            ("parakeet-v2-hf_float16_streaming150_decoder_step.aimodel/main.hash", 32),
            ("parakeet-v2-hf_float16_streaming150_decoder_step.aimodel/main.mlirb", 15_268_208),
            ("parakeet-v2-hf_float16_streaming150_decoder_step.aimodel/metadata.json", 457),
            ("parakeet-v2-hf_float16_streaming150_encoder.aimodel/main.hash", 32),
            ("parakeet-v2-hf_float16_streaming150_encoder.aimodel/main.mlirb", 1_183_887_050),
            ("parakeet-v2-hf_float16_streaming150_encoder.aimodel/metadata.json", 452),
            ("parakeet-v2-hf_float16_streaming150_joint.aimodel/main.hash", 32),
            ("parakeet-v2-hf_float16_streaming150_joint.aimodel/main.mlirb", 1_322_180),
            ("parakeet-v2-hf_float16_streaming150_joint.aimodel/metadata.json", 450),
            ("processor/processor_config.json", 417),
            ("processor/tokenizer.json", 389_203),
            ("processor/tokenizer_config.json", 307),
        ])

    func url(_ path: String) -> URL {
        URL(string: "https://huggingface.co/\(repo)/resolve/\(revision)/\(path)")!
    }

    /// Downloads every file into `<folder>.partial`, then moves it to `folder`, so a half-finished download never
    /// looks installed. `progress` gets the fraction done (0…1).
    func download(to folder: URL, progress: @escaping @Sendable (Double) -> Void) async throws {
        let fm = FileManager.default
        let free = (try? URL.applicationSupportDirectory.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]))?
            .volumeAvailableCapacityForImportantUsage ?? .max
        guard free > size + size / 4 else { throw DownloadError.noSpace(needed: size) }
        let partial = folder.appendingPathExtension("partial")
        try? fm.removeItem(at: partial)
        var done: Int64 = 0
        for file in files {
            let destination = partial.appending(path: file.path)
            try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            let before = done
            try await Fetch.file(url(file.path), to: destination) { written in
                progress(Double(before + written) / Double(size))
            }
            done += file.size
        }
        try? fm.removeItem(at: folder)
        try fm.moveItem(at: partial, to: folder)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true // re-downloadable, and far too big for iCloud backups
        var installed = folder
        try installed.setResourceValues(values)
    }
}

enum DownloadError: LocalizedError {
    case noSpace(needed: Int64)
    case http(Int)

    var errorDescription: String? {
        switch self {
        case .noSpace(let needed):
            "Not enough free space (needs about \(ByteCountFormatter.string(fromByteCount: needed, countStyle: .file)))"
        case .http(let status): "The server answered \(status)"
        }
    }
}

/// One file download with byte progress, moved into place as soon as it finishes.
private final class Fetch: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let destination: URL
    private let progress: @Sendable (Int64) -> Void
    private var continuation: CheckedContinuation<Void, Error>?
    private let lock = NSLock()

    private init(destination: URL, progress: @escaping @Sendable (Int64) -> Void) {
        self.destination = destination
        self.progress = progress
    }

    static func file(_ url: URL, to destination: URL, progress: @escaping @Sendable (Int64) -> Void) async throws {
        let fetch = Fetch(destination: destination, progress: progress)
        let session = URLSession(configuration: .default, delegate: fetch, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        try await withCheckedThrowingContinuation { continuation in
            fetch.continuation = continuation
            session.downloadTask(with: url).resume()
        }
    }

    private func finish(_ result: Result<Void, Error>) {
        lock.lock()
        let continuation = continuation
        self.continuation = nil
        lock.unlock()
        continuation?.resume(with: result)
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        progress(totalBytesWritten)
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        // The temporary file is deleted when this returns, so move it now.
        if let status = (downloadTask.response as? HTTPURLResponse)?.statusCode, status != 200 {
            return finish(.failure(DownloadError.http(status)))
        }
        do {
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.moveItem(at: location, to: destination)
            finish(.success(()))
        } catch {
            finish(.failure(error))
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error { finish(.failure(error)) }
    }
}
