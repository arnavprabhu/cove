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

    /// The view's task cancels polling on disappearance or a library-volume change.
    func poll(at url: URL) async {
        available = nil
        while !Task.isCancelled {
            update(available: HostInfo.freeDiskSpace(at: url))
            do { try await Task.sleep(for: .seconds(30)) }
            catch { return }
        }
    }
}
