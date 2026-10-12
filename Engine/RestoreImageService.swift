import Foundation
import Virtualization

enum RestoreImageService {
    static func fetchLatestSupported() async throws -> VZMacOSRestoreImage {
        try await withCheckedThrowingContinuation { cont in
            VZMacOSRestoreImage.fetchLatestSupported { cont.resume(with: $0) }
        }
    }

    static func load(from fileURL: URL) async throws -> VZMacOSRestoreImage {
        try await withCheckedThrowingContinuation { cont in
            VZMacOSRestoreImage.load(from: fileURL) { cont.resume(with: $0) }
        }
    }

    struct Info: Equatable {
        var url: URL
        var version: String
        var build: String
        var displayName: String { "\(MacOSNames.describe(version: version)) (\(build))" }
    }

    static func info(_ image: VZMacOSRestoreImage) -> Info {
        Info(url: image.url, version: MacOSNames.versionString(image.operatingSystemVersion), build: image.buildVersion)
    }
}

/// Resumable `.ipsw` download. Resume data is kept next to the destination as `<name>.resume`
/// so a failed or cancelled download continues across launches.
final class RestoreImageDownloader: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    typealias Progress = @MainActor (_ received: Int64, _ expected: Int64) -> Void

    private let remote: URL
    private let destination: URL
    private let onProgress: Progress
    private var continuation: CheckedContinuation<URL, Error>?
    private var task: URLSessionDownloadTask?
    private lazy var session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)

    var resumeDataURL: URL { destination.appendingPathExtension("resume") }

    init(remote: URL, destination: URL, onProgress: @escaping Progress) {
        self.remote = remote
        self.destination = destination
        self.onProgress = onProgress
    }

    var hasResumeData: Bool { FileManager.default.fileExists(atPath: resumeDataURL.path) }

    func start() async throws -> URL {
        if FileManager.default.fileExists(atPath: destination.path) { return destination }
        return try await withCheckedThrowingContinuation { cont in
            continuation = cont
            if let data = try? Data(contentsOf: resumeDataURL) {
                task = session.downloadTask(withResumeData: data)
            } else {
                task = session.downloadTask(with: remote)
            }
            task?.resume()
        }
    }

    /// Cancels and keeps resume data on disk.
    func cancel() {
        task?.cancel { [resumeDataURL] data in
            if let data { try? data.write(to: resumeDataURL) }
        }
    }

    /// Progress callbacks arrive many times a second; the UI only needs a few.
    private var lastReport = Date.distantPast

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData _: Int64,
                    totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        let now = Date()
        guard now.timeIntervalSince(lastReport) >= 0.2 || totalBytesWritten == totalBytesExpectedToWrite else { return }
        lastReport = now
        let cb = onProgress
        Task { @MainActor in cb(totalBytesWritten, totalBytesExpectedToWrite) }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        do {
            if let http = downloadTask.response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                throw CoveError.downloadFailed("Server returned \(http.statusCode).", resumable: false)
            }
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.moveItem(at: location, to: destination)
            try? FileManager.default.removeItem(at: resumeDataURL)
            finish(.success(destination))
        } catch {
            finish(.failure(error))
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error else { return }
        let ns = error as NSError
        if let data = ns.userInfo[NSURLSessionDownloadTaskResumeData] as? Data {
            try? data.write(to: resumeDataURL)
        }
        if ns.code == NSURLErrorCancelled {
            finish(.failure(CoveError.cancelled))
        } else {
            finish(.failure(CoveError.downloadFailed(error.localizedDescription, resumable: hasResumeData)))
        }
    }

    private func finish(_ result: Result<URL, Error>) {
        continuation?.resume(with: result)
        continuation = nil
        session.finishTasksAndInvalidate()
    }
}
