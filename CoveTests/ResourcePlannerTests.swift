import XCTest
@testable import Cove

final class ResourcePlannerTests: XCTestCase {
    private func planner(cores: Int = 12, memGB: Int = 36, freeGB: Int = 500) -> ResourcePlanner {
        ResourcePlanner(hostCores: cores, hostMemory: Bytes.gb(memGB), hostFreeDisk: Bytes.gb(freeGB))
    }

    func testBalancedDefaultsMatchDesign() {
        let r = planner().recommended(.balanced)
        XCTAssertEqual(r.cpu, 4)
        XCTAssertEqual(r.memory, Bytes.gb(8))
        XCTAssertEqual(r.disk, Bytes.gb(80))
    }

    func testClampsToImageMinimumsAndHostLimits() {
        var p = planner(cores: 8, memGB: 16)
        p.imageMinCPU = 2
        p.imageMinMemory = Bytes.gb(4)
        XCTAssertEqual(p.clampCPU(1), 2)
        XCTAssertEqual(p.clampCPU(64), 7)           // host keeps one core
        XCTAssertEqual(p.clampMemory(Bytes.gb(1)), Bytes.gb(4))
        XCTAssertEqual(p.clampMemory(Bytes.gb(64)), Bytes.gb(12)) // host keeps 4 GB
    }

    func testDiskLimitedByFreeSpace() {
        let p = planner(freeGB: 60)
        XCTAssertEqual(p.limits.maxDisk, Bytes.gb(40))
        XCTAssertEqual(p.recommended().disk, Bytes.gb(40))
    }

    func testHostRemainderWarning() {
        let p = planner()
        XCTAssertFalse(p.hostRemainder(cpu: 4, memory: Bytes.gb(8)).tight)
        let tight = p.hostRemainder(cpu: 11, memory: Bytes.gb(30))
        XCTAssertEqual(tight.cores, 1)
        XCTAssertEqual(tight.memoryGB, 6)
        XCTAssertTrue(tight.tight)
    }
}

final class VMConfigTests: XCTestCase {
    func testConfigRoundTripsThroughBundle() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "cove-test-\(UUID().uuidString).cove")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let bundle = VMBundle(url: dir)
        let cfg = VMConfig(name: "Tahoe Dev", cpuCount: 4, memoryBytes: Bytes.gb(8), diskBytes: Bytes.gb(80),
                           network: .bridged(interface: "en0"), osVersion: "26.0", osBuild: "25A100")
        try bundle.writeConfig(cfg)
        var read = try bundle.readConfig()
        // ISO 8601 keeps millisecond precision.
        XCTAssertEqual(read.createdAt.timeIntervalSince1970, cfg.createdAt.timeIntervalSince1970, accuracy: 0.001)
        read.createdAt = cfg.createdAt
        XCTAssertEqual(read, cfg)
    }

    func testSparseDiskGrowsButNeverShrinks() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "cove-disk-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let bundle = VMBundle(url: dir)
        try bundle.createSparseDisk(size: Bytes.gb(64))
        XCTAssertEqual(bundle.diskCapacity, Bytes.gb(64))
        XCTAssertLessThan(bundle.diskAllocated, Bytes.gb(1)) // sparse
        try bundle.resizeDisk(to: Bytes.gb(80))
        XCTAssertEqual(bundle.diskCapacity, Bytes.gb(80))
        XCTAssertThrowsError(try bundle.resizeDisk(to: Bytes.gb(10)))
    }

    func testHardwareChangeDetected() {
        let a = VMConfig(name: "A", cpuCount: 4, memoryBytes: Bytes.gb(8), diskBytes: Bytes.gb(80))
        var b = a
        b.name = "Renamed"
        XCTAssertEqual(a.hardwareFingerprint, b.hardwareFingerprint)
        b.cpuCount = 6
        XCTAssertNotEqual(a.hardwareFingerprint, b.hardwareFingerprint)
    }

    func testMacOSNames() {
        XCTAssertEqual(MacOSNames.describe(version: "15.2"), "macOS 15 Sequoia")
        XCTAssertEqual(MacOSNames.describe(version: "26.0"), "macOS 26 Tahoe")
    }
}
