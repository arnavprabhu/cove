import XCTest
@testable import Cove

final class EdgeStateTests: XCTestCase {
    @MainActor
    func testDiskSpaceThresholds() {
        XCTAssertEqual(DiskSpaceMonitor.level(for: DiskSpaceMonitor.warningThreshold), .normal)
        XCTAssertEqual(DiskSpaceMonitor.level(for: DiskSpaceMonitor.warningThreshold - 1), .warning)
        XCTAssertEqual(DiskSpaceMonitor.level(for: DiskSpaceMonitor.criticalThreshold), .warning)
        XCTAssertEqual(DiskSpaceMonitor.level(for: DiskSpaceMonitor.criticalThreshold - 1), .critical)
        XCTAssertEqual(DiskSpaceMonitor.level(for: 0), .critical)
    }

    @MainActor
    func testCriticalWarningOnlyChangesWhenCrossingIntoCritical() {
        let monitor = DiskSpaceMonitor()
        XCTAssertEqual(monitor.level, .normal)
        monitor.update(available: Bytes.gb(4))
        XCTAssertEqual(monitor.criticalRevision, 1)
        monitor.update(available: Bytes.gb(3))
        XCTAssertEqual(monitor.criticalRevision, 1)
        monitor.update(available: Bytes.gb(5))
        XCTAssertEqual(monitor.level, .warning)
        monitor.update(available: Bytes.gb(4))
        XCTAssertEqual(monitor.criticalRevision, 2)
    }

    @MainActor
    func testLicenseAlertCarriesRequestedVMAndSupportsOldCallers() {
        let config = VMConfig(name: "Clean Sonoma", cpuCount: 4, memoryBytes: Bytes.gb(8), diskBytes: Bytes.gb(80))
        let item = VMItem(bundle: VMBundle(url: URL(fileURLWithPath: "/nonexistent.cove")), config: config)
        XCTAssertEqual(CoveAlert.from(CoveError.licenseLimit, starting: item), .licenseLimit(startingVMID: item.id))
        XCTAssertEqual(CoveAlert.from(CoveError.licenseLimit), .licenseLimit(startingVMID: nil))
        XCTAssertEqual(CoveAlert.from(CoveError.notEnoughDiskSpace(needed: Bytes.gb(5), available: 42)), .lowDiskSpace(available: 42))
    }

    func testDeleteCopyIncludesAllocatedBytesAndSnapshotCount() {
        let bytes = UInt64(31_200_000_000)
        for count in [0, 1, 3] {
            let alert = CoveAlert.confirmDelete(vmID: UUID(), name: "Sequoia QA", snapshotCount: count, bytes: bytes)
            XCTAssertTrue(alert.message.contains("(\(Bytes.format(bytes)))"))
            XCTAssertTrue(alert.message.contains("shared folders"))
            if count == 0 { XCTAssertFalse(alert.message.contains("snapshot")) }
            else { XCTAssertTrue(alert.message.contains("\(count) snapshot\(count == 1 ? "" : "s")")) }
        }
    }

    @MainActor
    func testStartAndRestartCheckSpaceBeforeChangingTheVM() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "cove-space-test-\(UUID())")
        let library = VMLibrary(rootURL: root)
        let config = VMConfig(name: "Untouched", cpuCount: 4, memoryBytes: Bytes.gb(8), diskBytes: Bytes.gb(80))
        let item = VMItem(bundle: VMBundle(url: root.appending(path: "Untouched.cove")), config: config)
        // An unavailable volume reports zero space; no VM hardware is needed to verify the guard.
        try FileManager.default.removeItem(at: root)
        for restart in [false, true] {
            do {
                if restart { try await library.restart(item) }
                else { try await library.start(item) }
                XCTFail("Starting without available disk space must fail")
            } catch {
                XCTAssertEqual(error as? CoveError, .notEnoughDiskSpace(needed: HostInfo.minimumVMStartFreeSpace, available: 0))
            }
            XCTAssertNil(item.session)
            XCTAssertEqual(item.config, config)
        }
    }
}
