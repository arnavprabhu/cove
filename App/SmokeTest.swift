import AppKit

/// Headless engine check (milestone 1). Launch with `-coveSmoke <mode>`:
///   `fetch`   — resolve the latest restore image from Apple (no download).
///   `install` — full one-click path: download → create bundle → install → boot → shut down.
/// Prints progress to stdout and exits with status 0 on success.
@MainActor
enum SmokeTest {
    static var mode: String? {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-coveSmoke"), i + 1 < args.count else { return nil }
        return args[i + 1]
    }

    static func runIfRequested() {
        guard let mode else { return }
        Task {
            do {
                switch mode {
                case "fetch": try await fetch()
                case "install": try await install()
                default: log("unknown mode \(mode)"); exit(2)
                }
                log("OK")
                exit(0)
            } catch {
                log("FAILED: \(error.localizedDescription)")
                exit(1)
            }
        }
    }

    private static func log(_ s: String) {
        print("[cove-smoke] \(s)")
        fflush(stdout)
    }

    private static func fetch() async throws {
        log("host: \(HostInfo.chipName), \(HostInfo.cpuCount) cores, \(Bytes.formatMemory(HostInfo.memoryBytes)), \(HostInfo.osVersionString)")
        log("virtualization supported: \(HostInfo.virtualizationSupported)")
        let image = try await RestoreImageService.fetchLatestSupported()
        let info = RestoreImageService.info(image)
        log("latest: \(info.displayName) — \(info.url.absoluteString)")
        guard let req = image.mostFeaturefulSupportedConfiguration else { throw CoveError.restoreImageUnsupported }
        log("requirements: \(req.minimumSupportedCPUCount) CPUs, \(Bytes.formatMemory(req.minimumSupportedMemorySize)), hw supported: \(req.hardwareModel.isSupported)")
        log("library: \(VMLibrary.shared.rootURL.path)")
    }

    private static func install() async throws {
        let library = VMLibrary.shared
        let plan = HostInfo.planner(freeDiskAt: library.rootURL).recommended()
        var request = VMInstallJob.Request(name: "Smoke Test", cpuCount: plan.cpu, memoryBytes: plan.memory,
                                           diskBytes: plan.disk)
        request.startAfterInstall = false
        let job = library.beginInstall(request)
        var last = ""
        while !job.isFinished {
            let line = "\(job.stage.title) \(Int(job.stageProgress * 100))% overall \(Int(job.overallProgress * 100))% "
                + (Durations.remaining(job.estimatedSecondsRemaining) ?? "")
            if line != last { log(line); last = line }
            try await Task.sleep(for: .seconds(5))
        }
        guard job.status == .finished, let id = job.vmID, let item = library.item(id: id) else {
            throw CoveError.io("install ended with \(job.status)")
        }
        log("installed \(item.name) at \(item.bundle.url.path); snapshots: \(item.snapshots.map(\.name))")
        try await library.start(item)
        log("booted: \(item.state.label)")
        try await Task.sleep(for: .seconds(20))
        try await item.session?.suspend()
        log("suspended: \(item.state.label), save state present: \(item.bundle.hasSaveState)")
        try await library.start(item)
        log("resumed from save state: \(item.state.label)")
        try await item.session?.forceStop()
        log("stopped: \(item.state.label)")
    }
}
