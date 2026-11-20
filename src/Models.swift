import Foundation
import CryptoKit

struct Model: Decodable {
    let file, title, detail, digest: String
    let bytes: Int64
    let url: URL
    var cleanup: Bool { file.hasSuffix(".gguf") }
    var turns: Bool { file.contains("tdrz") }
    var size: String { ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file) }
}

struct Problem: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

final class ModelStore: NSObject, URLSessionDownloadDelegate {
    let folder: URL
    let catalog: [Model]
    private(set) var pending: Model?
    private var task: URLSessionDownloadTask?
    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 90
        return URLSession(configuration: config, delegate: self, delegateQueue: .main)
    }()
    var status: (String) -> Void = { _ in }
    var finished: (Model, Error?) -> Void = { _,_ in }

    override init() {
        folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Transcriber/Models", isDirectory: true)
        catalog = (try? JSONDecoder().decode([Model].self, from: Data(contentsOf:
            Bundle.main.url(forResource: "Models", withExtension: "json")!))) ?? []
        super.init()
    }

    func path(_ model: Model) -> URL { folder.appendingPathComponent(model.file) }
    func installed(_ model: Model) -> Bool {
        (try? path(model).resourceValues(forKeys: [.fileSizeKey]).fileSize).map { Int64($0) == model.bytes } ?? false
    }
    func download(_ model: Model) {
        guard pending == nil else { return }
        pending = model
        task = session.downloadTask(with: model.url)
        task?.resume()
        status("Connecting…")
    }
    func cancel() { task?.cancel() }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData: Int64,
                    totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard let model = pending, task == downloadTask else { return }
        status("Downloading \(model.title) · \(min(100, totalBytesWritten * 100 / model.bytes))%")
    }
    private func finish(_ model: Model, _ error: Error?) {
        task = nil
        pending = nil
        finished(model, error)
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error, let model = pending, self.task == task { finish(model, error) }
    }
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard let model = pending, task == downloadTask else { return }
        let fm = FileManager.default
        let staging = folder.appendingPathComponent(UUID().uuidString + ".partial")
        do {
            guard let http = downloadTask.response as? HTTPURLResponse, http.statusCode == 200 else {
                throw Problem("The model host could not provide this download. Please try again.")
            }
            try fm.createDirectory(at: folder, withIntermediateDirectories: true)
            try fm.moveItem(at: location, to: staging)
        } catch { finish(model, error); return }
        task = nil
        status("Checking download…")
        let destination = path(model)
        DispatchQueue.global(qos: .utility).async {
            let fm = FileManager.default
            do {
                defer { try? fm.removeItem(at: staging) }
                let handle = try FileHandle(forReadingFrom: staging)
                defer { handle.closeFile() }
                var sha = SHA256()
                while true {
                    let block = handle.readData(ofLength: 1 << 20)
                    if block.isEmpty { break }
                    sha.update(data: block)
                }
                guard sha.finalize().map({ String(format: "%02x", $0) }).joined() == model.digest else {
                    throw Problem("The downloaded file was incomplete or changed. Try the download again.")
                }
                if fm.fileExists(atPath: destination.path) {
                    _ = try fm.replaceItemAt(destination, withItemAt: staging)
                } else { try fm.moveItem(at: staging, to: destination) }
                DispatchQueue.main.async { self.finish(model, nil) }
            } catch { DispatchQueue.main.async { self.finish(model, error) } }
        }
    }
}
