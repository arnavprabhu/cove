import XCTest
@testable import Cove

final class GuestAccessTests: XCTestCase {
    private let leases = """
    {
    \tname=AppleViMachine1
    \tip_address=192.168.64.6
    \thw_address=1,1e:af:9b:bf:91:3b
    \tidentifier=1,1e:af:9b:bf:91:3b
    \tlease=0x6acc6a19
    }
    {
    \tip_address=192.168.64.5
    \thw_address=1,d2:7f:1:db:3f:6f
    \tlease=0x6ab5871a
    }
    {
    \tip_address=192.168.64.9
    \thw_address=1,d2:7f:1:db:3f:6f
    \tlease=0x6ab5ffff
    }
    """

    func testFindsIPByMAC() {
        XCTAssertEqual(GuestAccess.ipAddress(forMAC: "1e:af:9b:bf:91:3b", leases: leases), "192.168.64.6")
    }

    func testMatchesMACWithStrippedLeadingZerosAndPicksNewestLease() {
        // Cove stores "d2:7f:01:…"; bootpd writes "d2:7f:1:…". Two leases: newest wins.
        XCTAssertEqual(GuestAccess.ipAddress(forMAC: "D2:7F:01:DB:3F:6F", leases: leases), "192.168.64.9")
        XCTAssertNil(GuestAccess.ipAddress(forMAC: "aa:bb:cc:dd:ee:ff", leases: leases))
    }

    func testAlias() {
        XCTAssertEqual(GuestAccess.alias(for: "Smoke Test"), "cove-smoke-test")
        XCTAssertEqual(GuestAccess.alias(for: "Tahoe  Dev (beta)"), "cove-tahoe-dev-beta")
        XCTAssertEqual(GuestAccess.alias(for: "???"), "cove-vm")
    }

    func testOldConfigWithoutRemoteAccessDecodes() throws {
        let json = #"{"id":"6EBD31EA-90C4-42F4-B9BC-890551278522","name":"Old","cpuCount":4,"memoryBytes":8589934592,"diskBytes":85899345920,"display":{"widthInPixels":2560,"heightInPixels":1600,"pixelsPerInch":220,"matchesHost":true},"network":{"nat":{}},"shares":[],"audioEnabled":true,"createdAt":"2026-10-12T03:36:52.267Z","notes":""}"#
        let cfg = try VMBundle.decoder.decode(VMConfig.self, from: Data(json.utf8))
        XCTAssertNil(cfg.remoteAccess)
        XCTAssertFalse(cfg.access.enabled)
    }

    func testEnablingRemoteAccessIsAHardwareChange() {
        let a = VMConfig(name: "A", cpuCount: 4, memoryBytes: Bytes.gb(8), diskBytes: Bytes.gb(80))
        var b = a
        b.access.enabled = true
        XCTAssertNotEqual(a.hardwareFingerprint, b.hardwareFingerprint)
        var c = b
        c.access.passwordlessSudo = true   // only changes the script, not devices
        XCTAssertEqual(b.hardwareFingerprint, c.hardwareFingerprint)
    }

    func testSetupScriptHonoursSudoChoice() {
        let on = GuestAccess.setupScript(alias: "cove-x", passwordlessSudo: true)
        XCTAssertTrue(on.contains("NOPASSWD: ALL"))
        let off = GuestAccess.setupScript(alias: "cove-x", passwordlessSudo: false)
        XCTAssertFalse(off.contains("NOPASSWD"))
        XCTAssertTrue(off.contains("rm -f /etc/sudoers.d/cove"))
        XCTAssertTrue(off.contains(#"echo "$ME" > "$DIR/status/user""#))
    }
}
