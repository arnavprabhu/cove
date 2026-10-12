import Foundation
import Observation

/// Polls a volume without owning or depending on the VM library.
@MainActor @Observable
final class DiskSpaceMonitor {
    static let shared = DiskSpaceMonitor()
    static let warningThreshold = Bytes.gb(20)
    static let criticalThreshold = HostInfo.minimumVMStartFreeSpace

    enum Level { case normal, warning, critical }

    private(set) var available: UInt64?
    /// Changes only when entering critical space, so the app warns once per crossing.
    private(set) var criticalRevision = 0
    private var acknowledgedCriticalRevision = 0
    @ObservationIgnored private var pollingTask: Task<Void, Never>?

    init(available: UInt64? = nil) { self.available = available }

    var level: Level {
        guard let available else { return .normal }
        return Self.level(for: available)
    }

    static func level(for available: UInt64) -> Level {
        if available < criticalThreshold { return .critical }
        if available < warningThreshold { return .warning }
        return .normal
    }

    func update(available: UInt64) {
        let wasCritical = level == .critical
        self.available = available
        if !wasCritical && level == .critical { criticalRevision += 1 }
    }

    /// Shared by alert presenters so only one window warns per crossing.
    func takeCriticalWarning() -> UInt64? {
        guard level == .critical, criticalRevision > acknowledgedCriticalRevision else { return nil }
        acknowledgedCriticalRevision = criticalRevision
        return available
    }

    /// Keep polling when the Library window closes; the provider follows volume moves.
    func startPolling(at url: @escaping () -> URL) {
        guard pollingTask == nil else { return }
        pollingTask = Task {
            var currentURL: URL?
            while !Task.isCancelled {
                let nextURL = url()
                if nextURL != currentURL {
                    available = nil
                    currentURL = nextURL
                }
                update(available: HostInfo.freeDiskSpace(at: nextURL))
                do { try await Task.sleep(for: .seconds(30)) }
                catch { return }
            }
        }
    }
}
