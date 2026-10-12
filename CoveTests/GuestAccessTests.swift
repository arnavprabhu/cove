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
        XCTAssertTrue(off.contains(#"echo "$ME" > "$STATUS/user""#))
        XCTAssertTrue(off.contains(#"STATUS="/Volumes/My Shared Files/Cove Status""#))
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

@MainActor
final class HardeningTests: XCTestCase {
    private func tempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appending(path: "cove-hard-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        return dir
    }

    func testIncludeDetectionIgnoresComments() {
        XCTAssertTrue(GuestAccess.hasInclude("Include ~/.ssh/cove/config\nHost x\n"))
        XCTAssertTrue(GuestAccess.hasInclude("  include   ~/.ssh/cove/config"))
        XCTAssertFalse(GuestAccess.hasInclude("# Include ~/.ssh/cove/config"))
        XCTAssertFalse(GuestAccess.hasInclude("Include ~/.ssh/cove/config.old"))
        XCTAssertFalse(GuestAccess.hasInclude(""))
    }

    func testSymlinkedShareRootIsReplacedNotFollowed() throws {
        let dir = try tempDir()
        let secret = dir.appending(path: "secret")
        try FileManager.default.createDirectory(at: secret, withIntermediateDirectories: true)
        try Data("key".utf8).write(to: secret.appending(path: "id"))
        let share = dir.appending(path: "Guest")
        try FileManager.default.createSymbolicLink(at: share, withDestinationURL: secret)
        try GuestAccess.ensureRealDirectory(share)
        let attrs = try FileManager.default.attributesOfItem(atPath: share.path)
        XCTAssertEqual(attrs[.type] as? FileAttributeType, .typeDirectory)
        XCTAssertTrue(FileManager.default.fileExists(atPath: secret.appending(path: "id").path), "target untouched")
    }

    func testImportRefusesBundlesContainingSymlinks() throws {
        let dir = try tempDir()
        let bundle = dir.appending(path: "Evil.cove")
        try FileManager.default.createDirectory(at: bundle.appending(path: "Snapshots/x"), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(atPath: bundle.appending(path: "Snapshots/x/Disk.img").path,
                                                   withDestinationPath: "../../../SSH/cove_ed25519")
        XCTAssertEqual(VMLibrary.firstSymlink(in: bundle), "Snapshots/x/Disk.img")
        let library = VMLibrary(rootURL: dir.appending(path: "lib"))
        XCTAssertThrowsError(try library.importVM(from: bundle))
    }

    func testNamesThatCollideAsSSHAliasesAreNotUnique() throws {
        let dir = try tempDir()
        let library = VMLibrary(rootURL: dir)
        let url = library.vmsURL.appending(path: "Agent.cove")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        try VMBundle(url: url).writeConfig(VMConfig(name: "Agent", cpuCount: 2, memoryBytes: Bytes.gb(4), diskBytes: Bytes.gb(32)))
        library.reload()
        XCTAssertTrue(library.isNameTaken("agent", excluding: nil))
        XCTAssertTrue(library.isNameTaken("AGENT!", excluding: nil))
        XCTAssertEqual(library.uniqueName("agent"), "agent 2")
        XCTAssertFalse(library.isNameTaken("Agent", excluding: library.items.first?.id))
    }
}

final class GuestFileReadTests: XCTestCase {
    func testReadsSmallRegularFilesOnly() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "gfr-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try Data("testing\n".utf8).write(to: dir.appending(path: "user"))
        XCTAssertEqual(GuestAccess.readSmallGuestFile(dir.appending(path: "user")), "testing\n")

        try Data(repeating: 0x61, count: 10_000).write(to: dir.appending(path: "big"))
        XCTAssertNil(GuestAccess.readSmallGuestFile(dir.appending(path: "big")))

        try Data("secret".utf8).write(to: dir.appending(path: "target"))
        try FileManager.default.createSymbolicLink(atPath: dir.appending(path: "link").path, withDestinationPath: "target")
        XCTAssertNil(GuestAccess.readSmallGuestFile(dir.appending(path: "link")))

        let real = dir.appending(path: "realdir")
        try FileManager.default.createDirectory(at: real, withIntermediateDirectories: true)
        try Data("x".utf8).write(to: real.appending(path: "user"))
        try FileManager.default.createSymbolicLink(atPath: dir.appending(path: "linkdir").path, withDestinationPath: "realdir")
        XCTAssertNil(GuestAccess.readSmallGuestFile(dir.appending(path: "linkdir/user")))
    }
}
