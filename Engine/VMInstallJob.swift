import Foundation
import Virtualization

/// Drives the one-click create flow: Check Mac → Download → Install → First boot.
@MainActor @Observable
final class VMInstallJob: Identifiable {
    enum Source: Equatable {
        /// Latest supported build from Apple.
        case latest
        /// A local `.ipsw` (user-picked or from the RestoreImages cache).
        case file(URL)
    }

    struct Request {
        var name: String
        var source: Source = .latest
        var cpuCount: Int
        var memoryBytes: UInt64
        var diskBytes: UInt64
        var display: DisplaySettings = .matchHost
        var network: NetworkMode = .nat
        var shares: [SharedFolder] = []
        var startAfterInstall = true
        var keepRestoreImage = true
        var snapshotAfterInstall = true
        var purpose: VMPurpose = .everyday
        var remoteAccess = RemoteAccessSettings()
    }

    enum Stage: Int, CaseIterable, Comparable {
        case check, download, install, firstBoot, done
        static func < (a: Stage, b: Stage) -> Bool { a.rawValue < b.rawValue }

        var title: String {
            switch self {
            case .check: "Check this Mac"
            case .download: "Download restore image"
            case .install: "Install macOS"
            case .firstBoot: "First boot"
            case .done: "Done"
            }
        }
    }

    enum Status: Equatable {
        case running
        case failed(String, resumable: Bool)
        case cancelled
        case finished
    }

    let id = UUID()
    private(set) var request: Request
    private(set) var stage: Stage = .check
    private(set) var status: Status = .running
    /// 0…1 progress of the current stage.
    private(set) var stageProgress: Double = 0
    private(set) var bytesReceived: Int64 = 0
    private(set) var bytesExpected: Int64 = 0
    /// Seconds left in the current stage, when known.
    private(set) var estimatedSecondsRemaining: TimeInterval?
    private(set) var restoreImageInfo: RestoreImageService.Info?
    private(set) var vmID: UUID?
    /// The UI sets this when the user picks "Continue in Background"; a notification is posted on completion.
    var isInBackground = false
    /// Hook for the app to open the VM window after install (set by the app shell).
    var onReadyToBoot: ((VMItem) -> Void)?

    var isFinished: Bool { status != .running }

    private weak var library: VMLibrary?
    /// The installer's VM while macOS is being written; counts toward the two-guest limit.
    private(set) var installerVM: VZVirtualMachine?
    /// Set once macOS is on the disk. From then on the VM is kept no matter what happens next.
    private(set) var installed = false
    /// Why the optional first boot didn't happen (the VM itself is fine).
    private(set) var firstBootMessage: String?
    private var task: Task<Void, Never>?
    private var downloader: RestoreImageDownloader?
    private var progressObservation: NSKeyValueObservation?
    private var rateSampler = RateSampler()
    private var lastInstallReport = Date.distantPast

    init(request: Request, library: VMLibrary) {
        self.request = request
        self.library = library
    }

    func run() {
        status = .running
        task = Task { await execute() }
    }

    /// Retry after a failure (downloads resume from where they stopped).
    func retry(using file: URL? = nil) {
        guard case .failed = status else { return }
        if let file { request.source = .file(file) }
        installed = false
        firstBootMessage = nil
        run()
    }

    /// Stops the job. Partial files are removed by the pipeline itself once the installer has actually stopped —
    /// deleting them here would pull the disk out from under a running installer.
    func cancel() {
        guard status == .running else { return }
        status = .cancelled
        downloader?.cancel()
        task?.cancel()
    }

    #if DEBUG
    /// A failed download with no network or VM work, for the PNG render harness.
    static func failedDownloadSample(in library: VMLibrary) -> VMInstallJob {
        let job = VMInstallJob(request: Request(name: "Clean Sonoma", cpuCount: 4, memoryBytes: Bytes.gb(8),
                                               diskBytes: Bytes.gb(80)), library: library)
        job.stage = .download
        job.stageProgress = 0.62
        job.bytesExpected = 27_000_000_000
        job.bytesReceived = 16_740_000_000
        job.status = .failed("The connection to Apple was lost.", resumable: true)
        return job
    }

    /// A download in progress, for the PNG render harness.
    static func downloadingSample(in library: VMLibrary) -> VMInstallJob {
        let job = VMInstallJob(request: Request(name: "Agent Sandbox", cpuCount: 4, memoryBytes: Bytes.gb(8),
                                               diskBytes: Bytes.gb(80)), library: library)
        job.stage = .download
        job.stageProgress = 0.04
        job.bytesExpected = 26_640_000_000
        job.bytesReceived = 935_200_000
        job.estimatedSecondsRemaining = 360
        return job
    }
    #endif

    // MARK: Pipeline

    private func execute() async {
        guard let library else { return }
        var accessedFile: URL?
        defer { accessedFile?.stopAccessingSecurityScopedResource() }
        do {
            // 1. Check this Mac
            enter(.check)
            guard HostInfo.isAppleSilicon, HostInfo.virtualizationSupported else { throw CoveError.unsupportedHost }
            let free = HostInfo.freeDiskSpace(at: library.rootURL)
            let needed = HostInfo.estimatedInstallFootprint
            guard free >= needed else { throw CoveError.notEnoughDiskSpace(needed: needed, available: free) }
            stageProgress = 1

            // 2. Restore image
            enter(.download)
            let ipsw: URL
            switch request.source {
            case .latest:
                let remote = try await RestoreImageService.fetchLatestSupported()
                restoreImageInfo = RestoreImageService.info(remote)
                let dest = library.restoreImagesURL.appending(path: remote.url.lastPathComponent)
                let dl = RestoreImageDownloader(remote: remote.url, destination: dest) { [weak self] got, total in
                    self?.updateDownload(got, total)
                }
                downloader = dl
                ipsw = try await dl.start()
                downloader = nil
            case .file(let url):
                if url.startAccessingSecurityScopedResource() { accessedFile = url }
                ipsw = url
            }
            try Task.checkCancellation()
            let image = try await RestoreImageService.load(from: ipsw)
            restoreImageInfo = RestoreImageService.info(image)
            guard let requirements = image.mostFeaturefulSupportedConfiguration,
                  requirements.hardwareModel.isSupported else { throw CoveError.restoreImageUnsupported }
            stageProgress = 1

            // 3. Install — the installer runs a macOS guest, so it needs one of the two slots.
            enter(.install)
            guard library.canStartAnother else { throw CoveError.licenseLimit }
            let item = try createBundle(requirements: requirements, library: library)
            let session = try VMSession(bundle: item.bundle, config: item.config)
            installerVM = session.virtualMachine
            let installer = VZMacOSInstaller(virtualMachine: session.virtualMachine, restoringFromImageAt: ipsw)
            rateSampler = RateSampler()
            progressObservation = installer.progress.observe(\.fractionCompleted, options: [.new]) { [weak self] p, _ in
                let f = p.fractionCompleted
                Task { @MainActor in self?.updateInstall(f) }
            }
            try await withTaskCancellationHandler {
                try await installer.install()
            } onCancel: {
                Task { @MainActor in installer.progress.cancel() }
            }
            progressObservation = nil
            if session.virtualMachine.canStop { try? await session.virtualMachine.stop() }
            installerVM = nil
            installed = true
            item.installJob = nil

            if request.snapshotAfterInstall {
                _ = try? await SnapshotStore.take(item, name: "Fresh install")
            }
            if case .latest = request.source, !request.keepRestoreImage {
                try? FileManager.default.removeItem(at: ipsw)
            }

            // 4. First boot — optional. If it can't happen now (e.g. two VMs already running), keep the VM.
            enter(.firstBoot)
            if request.startAfterInstall {
                do {
                    try await library.start(item)
                    onReadyToBoot?(item)
                } catch {
                    firstBootMessage = error.localizedDescription
                }
            }
            stageProgress = 1
            enter(.done)
            status = .finished
            library.noteStorageChanged()
            InstallNotifier.postReady(vmName: item.name, vmID: item.id)
        } catch {
            progressObservation = nil
            await cleanUpAfterStop(library: library)
            // cancel() already set the status; the installer reports cancellation as an NSError.
            if status == .cancelled || error is CancellationError || (error as? CoveError) == .cancelled {
                status = .cancelled
                return
            }
            let resumable: Bool
            if case CoveError.downloadFailed(_, let r) = error { resumable = r } else { resumable = false }
            status = .failed(error.localizedDescription, resumable: resumable)
            InstallNotifier.postFailed(vmName: request.name, message: error.localizedDescription)
        }
    }

    /// After a failure or cancel: stop the installer VM first, then remove a VM that never finished installing.
    private func cleanUpAfterStop(library: VMLibrary) async {
        if let vm = installerVM {
            if vm.canStop { try? await vm.stop() }
            installerVM = nil
        }
        guard !installed, let id = vmID, let item = library.item(id: id) else { return }
        library.discard(item)
        vmID = nil
    }

    private func createBundle(requirements: VZMacOSConfigurationRequirements, library: VMLibrary) throws -> VMItem {
        var planner = HostInfo.planner(freeDiskAt: library.rootURL)
        planner.imageMinCPU = requirements.minimumSupportedCPUCount
        planner.imageMinMemory = requirements.minimumSupportedMemorySize
        let name = library.uniqueName(request.name.isEmpty ? "macOS" : request.name)
        let config = VMConfig(
            name: name,
            cpuCount: planner.clampCPU(request.cpuCount),
            memoryBytes: planner.clampMemory(request.memoryBytes),
            diskBytes: planner.clampDisk(request.diskBytes),
            display: request.display,
            network: request.network,
            macAddress: VZMACAddress.randomLocallyAdministered().string,
            shares: request.shares,
            osVersion: restoreImageInfo?.version,
            osBuild: restoreImageInfo?.build,
            purpose: request.purpose,
            remoteAccess: request.remoteAccess.enabled ? request.remoteAccess : nil)
        let url = library.vmsURL.appending(path: "\(library.sanitize(name)).\(VMBundle.pathExtension)")
        let bundle = try VMBundle.create(at: url, config: config, hardwareModel: requirements.hardwareModel)
        let item = library.registerInstalling(bundle: bundle, config: config, job: self)
        vmID = item.id
        return item
    }

    private func enter(_ s: Stage) {
        stage = s
        stageProgress = 0
        estimatedSecondsRemaining = nil
        rateSampler = RateSampler()
    }

    private func updateDownload(_ got: Int64, _ total: Int64) {
        bytesReceived = got
        bytesExpected = total
        guard total > 0 else { return }
        stageProgress = Double(got) / Double(total)
        estimatedSecondsRemaining = rateSampler.estimate(progress: stageProgress)
    }

    private func updateInstall(_ fraction: Double) {
        let now = Date()
        guard now.timeIntervalSince(lastInstallReport) >= 0.2 || fraction >= 1 else { return }
        lastInstallReport = now
        stageProgress = fraction
        estimatedSecondsRemaining = rateSampler.estimate(progress: fraction)
    }

    /// Overall 0…1 across stages, weighted roughly by duration.
    var overallProgress: Double {
        let weights: [Stage: Double] = [.check: 0.02, .download: 0.45, .install: 0.48, .firstBoot: 0.05]
        var done = 0.0
        for s in Stage.allCases where s < stage { done += weights[s] ?? 0 }
        return min(1, done + (weights[stage] ?? 0) * stageProgress)
    }
}

/// Smoothed progress-rate → time-remaining estimate.
struct RateSampler {
    private var start = Date()
    private var startProgress: Double?

    mutating func estimate(progress: Double) -> TimeInterval? {
        guard let p0 = startProgress else { startProgress = progress; start = Date(); return nil }
        let elapsed = Date().timeIntervalSince(start)
        let delta = progress - p0
        guard elapsed > 3, delta > 0.001 else { return nil }
        return (1 - progress) * elapsed / delta
    }
}
