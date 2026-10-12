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

    func testHostSSHDirectoryAcceptsHomeOrSSHFolder() {
        let home = URL(fileURLWithPath: "/Users/example", isDirectory: true)
        let ssh = home.appending(path: ".ssh", directoryHint: .isDirectory)
        XCTAssertEqual(GuestAccess.sshDirectory(in: home), ssh)
        XCTAssertEqual(GuestAccess.sshDirectory(in: ssh), ssh)
    }

    func testWalkthroughGatesStaleStatusAndRestart() {
        let status = GuestAccessMonitor.Status(ip: "192.168.64.6", sshReachable: true, guestUser: "arnav")
        var progress = RemoteAccessProgress(enabled: false, isLive: true, needsRestart: false,
                                            status: status, hostInstalled: true)
        XCTAssertFalse(progress.ready)
        XCTAssertEqual(progress.currentStep, 1)
        progress.enabled = true
        progress.needsRestart = true
        XCTAssertFalse(progress.ready)
        XCTAssertEqual(progress.currentStep, 1)
        progress.needsRestart = false
        progress.isLive = false
        XCTAssertFalse(progress.ready)
        XCTAssertEqual(progress.currentStep, 2)
        progress.isLive = true
        XCTAssertTrue(progress.ready)
        XCTAssertTrue(progress.completed.allSatisfy { $0 })
    }

    func testWalkthroughAdvancesThroughGuestAndHostSetup() {
        var progress = RemoteAccessProgress(enabled: true, isLive: true, needsRestart: false,
                                            status: .init(ip: "192.168.64.6"), hostInstalled: false)
        XCTAssertEqual(progress.currentStep, 3)
        progress.status.guestUser = "arnav"
        XCTAssertEqual(progress.currentStep, 4)
        progress.status.sshReachable = true
        XCTAssertTrue(progress.ready)
        XCTAssertEqual(progress.currentStep, 5)
        progress.status.ip = nil
        XCTAssertFalse(progress.ready)
        XCTAssertEqual(progress.currentStep, 4)
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

    func testSetupScriptIsValidShell() throws {
        for sudo in [true, false] {
            let url = FileManager.default.temporaryDirectory.appending(path: "cove-setup-\(UUID().uuidString).sh")
            try GuestAccess.setupScript(alias: "cove-x", passwordlessSudo: sudo).write(to: url, atomically: true, encoding: .utf8)
            defer { try? FileManager.default.removeItem(at: url) }
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/bin/sh")
            p.arguments = ["-n", url.path]
            try p.run(); p.waitUntilExit()
            XCTAssertEqual(p.terminationStatus, 0, "setup.sh (sudo: \(sudo)) has a syntax error")
        }
    }
}

final class GuestInputSanitizingTests: XCTestCase {
    func testRejectsSSHConfigInjectionInGuestUser() {
        XCTAssertEqual(GuestAccess.sanitizedUserName("testing\n"), "testing")
        XCTAssertNil(GuestAccess.sanitizedUserName("arnav\n\nHost *\n  ProxyCommand /usr/bin/osascript -e 'x'"))
        XCTAssertNil(GuestAccess.sanitizedUserName("a b"))
        XCTAssertNil(GuestAccess.sanitizedUserName("-oProxyCommand=x"))
        XCTAssertNil(GuestAccess.sanitizedUserName(String(repeating: "a", count: 33)))
        XCTAssertEqual(GuestAccess.sanitizedUserName("_svc.dev-1"), "_svc.dev-1")
    }

    func testIPv4Validation() {
        XCTAssertEqual(GuestAccess.sanitizedIPv4("192.168.64.6"), "192.168.64.6")
        XCTAssertNil(GuestAccess.sanitizedIPv4("192.168.64.6\n  ProxyCommand x"))
        XCTAssertNil(GuestAccess.sanitizedIPv4("192.168.64.256"))
        XCTAssertNil(GuestAccess.sanitizedIPv4("evil.example.com"))
    }

    func testLeaseWithInjectedIPIsIgnored() {
        let leases = "{\n\tip_address=1.2.3.4 ProxyCommand x\n\thw_address=1,aa:bb:cc:dd:ee:ff\n\tlease=0x1\n}"
        XCTAssertNil(GuestAccess.ipAddress(forMAC: "aa:bb:cc:dd:ee:ff", leases: leases))
    }

    func testConfigTokenGuard() {
        XCTAssertTrue(GuestAccess.isSafeConfigToken("cove-smoke-test"))
        XCTAssertFalse(GuestAccess.isSafeConfigToken("a\nb"))
        XCTAssertFalse(GuestAccess.isSafeConfigToken("a b"))
        XCTAssertFalse(GuestAccess.isSafeConfigToken("a#b"))
    }
}

final class FileCloneTests: XCTestCase {
    func testCloneReplacesAtomicallyAndKeepsDestinationOnFailure() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "clone-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let src = dir.appending(path: "src"), dst = dir.appending(path: "dst")
        try Data("new".utf8).write(to: src)
        try Data("old".utf8).write(to: dst)
        try FileClone.clone(src, to: dst)
        XCTAssertEqual(try String(contentsOf: dst, encoding: .utf8), "new")

        // A missing source must fail without touching the existing destination or leaving temp files.
        XCTAssertThrowsError(try FileClone.clone(dir.appending(path: "missing"), to: dst))
        XCTAssertEqual(try String(contentsOf: dst, encoding: .utf8), "new")
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: dir.path).sorted(), ["dst", "src"])
    }
}
