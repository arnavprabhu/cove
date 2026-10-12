import Foundation

/// Picks and clamps CPU / memory / disk for a new or edited VM. Pure logic so it's testable.
struct ResourcePlanner {
    struct Limits: Equatable {
        var minCPU: Int
        var maxCPU: Int
        var minMemory: UInt64
        var maxMemory: UInt64
        var minDisk: UInt64 = Bytes.gb(32)
        var maxDisk: UInt64
    }

    enum Profile: String, Codable, CaseIterable, Identifiable {
        case light, balanced, performance
        var id: String { rawValue }
        var label: String {
            switch self {
            case .light: "Light"
            case .balanced: "Balanced"
            case .performance: "Performance"
            }
        }
    }

    var hostCores: Int
    var hostMemory: UInt64
    var hostFreeDisk: UInt64
    /// Framework limits (VZVirtualMachineConfiguration.minimum/maximumAllowed*).
    var frameworkMinCPU: Int = 1
    var frameworkMaxCPU: Int = .max
    var frameworkMinMemory: UInt64 = Bytes.gb(2)
    var frameworkMaxMemory: UInt64 = .max
    /// Restore image requirements (VZMacOSConfigurationRequirements).
    var imageMinCPU: Int = 2
    var imageMinMemory: UInt64 = Bytes.gb(4)

    var limits: Limits {
        let minCPU = max(frameworkMinCPU, imageMinCPU)
        // Always leave the host at least one core and 4 GB.
        let maxCPU = max(minCPU, min(frameworkMaxCPU, hostCores - 1))
        let minMem = max(frameworkMinMemory, imageMinMemory)
        let hostCap = hostMemory > Bytes.gb(8) ? hostMemory - Bytes.gb(4) : hostMemory / 2
        let maxMem = max(minMem, min(frameworkMaxMemory, hostCap))
        let maxDisk = max(Bytes.gb(32), min(Bytes.gb(2048), hostFreeDisk > Bytes.gb(20) ? hostFreeDisk - Bytes.gb(20) : Bytes.gb(32)))
        return Limits(minCPU: minCPU, maxCPU: maxCPU, minMemory: minMem, maxMemory: maxMem, maxDisk: maxDisk)
    }

    func recommended(_ profile: Profile = .balanced) -> (cpu: Int, memory: UInt64, disk: UInt64) {
        let l = limits
        let cpu: Int
        let mem: UInt64
        switch profile {
        case .light:
            cpu = l.minCPU
            mem = l.minMemory
        case .balanced:
            cpu = min(4, hostCores / 2)
            mem = min(Bytes.gb(8), hostMemory / 4)
        case .performance:
            cpu = hostCores / 2
            mem = hostMemory / 2
        }
        let disk = min(Bytes.gb(80), l.maxDisk)
        return (clampCPU(cpu), clampMemory(mem), clampDisk(disk))
    }

    func clampCPU(_ v: Int) -> Int { min(max(v, limits.minCPU), limits.maxCPU) }

    func clampMemory(_ v: UInt64) -> UInt64 {
        // Framework requires a multiple of 1 MiB.
        let mib: UInt64 = 1 << 20
        let rounded = (v / mib) * mib
        return min(max(rounded, limits.minMemory), limits.maxMemory)
    }

    func clampDisk(_ v: UInt64) -> UInt64 { min(max(v, limits.minDisk), limits.maxDisk) }

    /// "Your Mac keeps X cores and Y GB" plus whether that's tight.
    func hostRemainder(cpu: Int, memory: UInt64) -> (cores: Int, memoryGB: Int, tight: Bool) {
        let cores = hostCores - cpu
        let memGB = Bytes.toGB(hostMemory > memory ? hostMemory - memory : 0)
        return (cores, memGB, cores < 2 || memGB < 8)
    }
}
