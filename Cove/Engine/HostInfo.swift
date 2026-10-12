import AppKit
import Network
import Virtualization

enum HostInfo {
    static var isAppleSilicon: Bool {
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size
        return sysctlbyname("hw.optional.arm64", &value, &size, nil, 0) == 0 && value == 1
    }

    static var virtualizationSupported: Bool { VZVirtualMachine.isSupported }

    static var cpuCount: Int { ProcessInfo.processInfo.processorCount }

    static var memoryBytes: UInt64 { ProcessInfo.processInfo.physicalMemory }

    static var osVersionString: String {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        return "macOS \(v.majorVersion).\(v.minorVersion)" + (v.patchVersion > 0 ? ".\(v.patchVersion)" : "")
    }

    /// e.g. "Mac15,8"
    static var modelIdentifier: String {
        var size = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        var buf = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.model", &buf, &size, nil, 0)
        return String(cString: buf)
    }

    /// e.g. "Apple M3 Max"
    static var chipName: String {
        var size = 0
        sysctlbyname("machdep.cpu.brand_string", nil, &size, nil, 0)
        var buf = [CChar](repeating: 0, count: max(size, 1))
        sysctlbyname("machdep.cpu.brand_string", &buf, &size, nil, 0)
        return String(cString: buf)
    }

    static func freeDiskSpace(at url: URL) -> UInt64 {
        let v = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return UInt64(max(0, v?.volumeAvailableCapacityForImportantUsage ?? 0))
    }

    /// Rough space a fresh install needs: restore image (~18 GB) + installed system (~25 GB).
    static let estimatedInstallFootprint: UInt64 = Bytes.gb(45)

    static func planner(freeDiskAt url: URL) -> ResourcePlanner {
        ResourcePlanner(
            hostCores: cpuCount,
            hostMemory: memoryBytes,
            hostFreeDisk: freeDiskSpace(at: url),
            frameworkMinCPU: VZVirtualMachineConfiguration.minimumAllowedCPUCount,
            frameworkMaxCPU: VZVirtualMachineConfiguration.maximumAllowedCPUCount,
            frameworkMinMemory: VZVirtualMachineConfiguration.minimumAllowedMemorySize,
            frameworkMaxMemory: VZVirtualMachineConfiguration.maximumAllowedMemorySize)
    }
}

/// Live network reachability for the Welcome screen's readiness checks.
@MainActor @Observable
final class NetworkMonitor {
    static let shared = NetworkMonitor()
    private(set) var isReachable = true
    private let monitor = NWPathMonitor()

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in self?.isReachable = path.status == .satisfied }
        }
        monitor.start(queue: DispatchQueue(label: "cove.network-monitor"))
    }
}
