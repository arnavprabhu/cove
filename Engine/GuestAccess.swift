import AppKit
import Network

/// SSH & agent access to macOS guests.
///
/// How it fits together:
/// 1. Cove keeps one ed25519 key pair for the library (`<Library>/SSH/cove_ed25519`, made with `ssh-keygen`).
/// 2. With remote access on, the VM gets a "Cove" shared folder (`<bundle>/Guest`) holding the public key and
///    `setup.sh`. In the guest the user runs `sh "/Volumes/My Shared Files/Cove/setup.sh"` once: it enables
///    Remote Login, authorizes the key, optionally allows passwordless sudo, and writes the guest user name back.
/// 3. The VM's IP comes from the NAT DHCP lease table, matched on the VM's fixed MAC address.
/// 4. Optionally Cove installs itself into `~/.ssh` (user-granted folder access): key copy, `~/.ssh/cove/config`
///    with a `Host cove-<name>` entry per VM kept up to date, and an `Include` line in `~/.ssh/config`, so the
///    user and coding agents can run `ssh cove-<name>`.
@MainActor
enum GuestAccess {
    nonisolated static let shareName = "Cove"
    nonisolated static let guestFolderPath = "/Volumes/My Shared Files/\(shareName)"
    nonisolated static let setupCommand = #"sh "/Volumes/My Shared Files/Cove/setup.sh""#
    nonisolated static let keyName = "cove_ed25519"
    nonisolated static let leasesPath = "/var/db/dhcpd_leases"

    // MARK: Naming

    /// SSH host alias, e.g. "Smoke Test" → "cove-smoke-test".
    nonisolated static func alias(for name: String) -> String {
        let slug = name.lowercased().unicodeScalars.map { CharacterSet.alphanumerics.contains($0) ? Character($0) : "-" }
        let collapsed = String(slug).split(separator: "-").joined(separator: "-")
        return "cove-" + (collapsed.isEmpty ? "vm" : collapsed)
    }

    // MARK: Keys

    static func keyURL(in library: VMLibrary) -> URL {
        library.rootURL.appending(path: "SSH", directoryHint: .isDirectory).appending(path: keyName)
    }

    /// Creates the library key pair on first use. Returns the public key line.
    @discardableResult
    static func ensureKeyPair(in library: VMLibrary) throws -> String {
        let key = keyURL(in: library)
        let pub = key.appendingPathExtension("pub")
        let fm = FileManager.default
        if !fm.fileExists(atPath: key.path) || !fm.fileExists(atPath: pub.path) {
            try fm.createDirectory(at: key.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? fm.removeItem(at: key)
            try? fm.removeItem(at: pub)
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/ssh-keygen")
            p.arguments = ["-q", "-t", "ed25519", "-N", "", "-C", "cove@\(Host.current().localizedName ?? "mac")", "-f", key.path]
            try p.run()
            p.waitUntilExit()
            guard p.terminationStatus == 0 else { throw CoveError.io("Couldn’t create an SSH key (ssh-keygen exited \(p.terminationStatus)).") }
        }
        return try String(contentsOf: pub, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: Guest folder

    /// Writes the files the guest sees at /Volumes/My Shared Files/Cove. Safe to call before every start.
    static func prepareGuestFolder(for item: VMItem, library: VMLibrary) throws {
        let pubKey = try ensureKeyPair(in: library)
        let dir = item.bundle.guestFolderURL
        let fm = FileManager.default
        try fm.createDirectory(at: dir.appending(path: "status"), withIntermediateDirectories: true)
        try (pubKey + "\n").write(to: dir.appending(path: "\(keyName).pub"), atomically: true, encoding: .utf8)
        try setupScript(alias: alias(for: item.name), passwordlessSudo: item.config.access.passwordlessSudo)
            .write(to: dir.appending(path: "setup.sh"), atomically: true, encoding: .utf8)
        // Sandboxed apps can't clear the quarantine flag on files they write, so the guest runs the script via
        // `sh` (which ignores quarantine) rather than double-clicking a .command file.
        try readme.write(to: dir.appending(path: "README.txt"), atomically: true, encoding: .utf8)
    }

    nonisolated static func setupScript(alias: String, passwordlessSudo: Bool) -> String {
        """
        #!/bin/sh
        # Cove guest setup — enables SSH (Remote Login) and authorizes Cove's key for this user.
        # Run in the VM's Terminal:  sh "/Volumes/My Shared Files/Cove/setup.sh"
        set -e
        DIR="$(cd "$(dirname "$0")" && pwd)"
        ME="$(id -un)"
        echo "Cove: setting up SSH for $ME. macOS will ask for your password."

        # systemsetup needs Full Disk Access on recent macOS and can fail quietly, so always ensure sshd via launchd.
        sudo systemsetup -setremotelogin on >/dev/null 2>&1 || true
        sudo launchctl enable system/com.openssh.sshd
        sudo launchctl bootstrap system /System/Library/LaunchDaemons/ssh.plist 2>/dev/null || true
        sleep 1
        if ! nc -z 127.0.0.1 22 >/dev/null 2>&1; then
          echo "Cove: SSH didn't start. Turn on System Settings ▸ General ▸ Sharing ▸ Remote Login, then run this again."
          exit 1
        fi

        mkdir -p "$HOME/.ssh" && chmod 700 "$HOME/.ssh"
        touch "$HOME/.ssh/authorized_keys" && chmod 600 "$HOME/.ssh/authorized_keys"
        KEY="$(cat "$DIR/\(keyName).pub")"
        grep -qxF "$KEY" "$HOME/.ssh/authorized_keys" || echo "$KEY" >> "$HOME/.ssh/authorized_keys"

        \(passwordlessSudo ? """
        echo "$ME ALL=(ALL) NOPASSWD: ALL" | sudo tee /etc/sudoers.d/cove >/dev/null
        sudo chmod 440 /etc/sudoers.d/cove
        """ : """
        sudo rm -f /etc/sudoers.d/cove
        """)

        sudo scutil --set LocalHostName "\(alias)" 2>/dev/null || true

        mkdir -p "$DIR/status"
        echo "$ME" > "$DIR/status/user"
        date -u +%Y-%m-%dT%H:%M:%SZ > "$DIR/status/configured"
        echo "Cove: done. Your Mac can now connect with: ssh \(alias)"
        """
    }

    nonisolated static let readme = """
    Cove — SSH & agent access

    Run this once in Terminal (inside this VM):

        sh "/Volumes/My Shared Files/Cove/setup.sh"

    It turns on Remote Login, authorizes Cove's SSH key for your user and reports back to Cove.
    Your Mac can then connect with `ssh cove-<vm-name>` (see Cove ▸ SSH & Agent Access).
    """

    /// The guest user reported by setup.sh, if it has run.
    static func guestUser(for item: VMItem) -> String? {
        let url = item.bundle.guestFolderURL.appending(path: "status/user")
        return (try? String(contentsOf: url, encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
    }

    // MARK: Network

    /// "6e:0b:4a:…" → "6e:b:4a:…" (bootpd drops leading zeros).
    nonisolated static func leaseFormMAC(_ mac: String) -> String {
        mac.lowercased().split(separator: ":").map { part in
            let trimmed = part.drop { $0 == "0" }
            return trimmed.isEmpty ? "0" : String(trimmed)
        }.joined(separator: ":")
    }

    /// Parses the bootpd lease table and returns the newest IP for `mac`.
    nonisolated static func ipAddress(forMAC mac: String, leases: String? = nil) -> String? {
        guard let text = leases ?? (try? String(contentsOfFile: leasesPath, encoding: .utf8)) else { return nil }
        let want = leaseFormMAC(mac)
        var best: (ip: String, lease: UInt64)?
        for block in text.components(separatedBy: "}") {
            var fields: [String: String] = [:]
            for line in block.split(separator: "\n") {
                let parts = line.trimmingCharacters(in: .whitespaces).split(separator: "=", maxSplits: 1)
                if parts.count == 2 { fields[String(parts[0])] = String(parts[1]) }
            }
            guard let hw = fields["hw_address"], let ip = fields["ip_address"] else { continue }
            // "1,1e:af:9b:bf:91:3b" — type prefix then MAC.
            let hwMAC = hw.split(separator: ",", maxSplits: 1).last.map(String.init) ?? hw
            guard leaseFormMAC(hwMAC) == want else { continue }
            let lease = fields["lease"].flatMap { UInt64($0.replacingOccurrences(of: "0x", with: ""), radix: 16) } ?? 0
            if best == nil || lease > best!.lease { best = (ip, lease) }
        }
        return best?.ip
    }

    /// True if something accepts TCP connections on port 22 within `timeout`.
    nonisolated static func isSSHReachable(_ host: String, timeout: TimeInterval = 1.5) async -> Bool {
        await withCheckedContinuation { cont in
            let conn = NWConnection(host: NWEndpoint.Host(host), port: 22, using: .tcp)
            let once = OnceFlag()
            let finish: (Bool) -> Void = { ok in
                guard once.set() else { return }
                conn.cancel()
                cont.resume(returning: ok)
            }
            conn.stateUpdateHandler = { state in
                switch state {
                case .ready: finish(true)
                case .failed, .cancelled: finish(false)
                case .waiting: finish(false)
                default: break
                }
            }
            conn.start(queue: .global(qos: .utility))
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) { finish(false) }
        }
    }

    // MARK: Commands

    /// What to type on the Mac. Uses the alias once Cove is installed in ~/.ssh, otherwise a full command.
    nonisolated static func sshCommand(alias: String, user: String?, ip: String?, keyPath: String, hostInstalled: Bool) -> String {
        if hostInstalled { return "ssh \(alias)" }
        let target = "\(user ?? "<user>")@\(ip ?? "<vm-ip>")"
        return "ssh -i \"\(keyPath)\" \(target)"
    }

    /// Paste-ready block for CLAUDE.md / AGENTS.md.
    nonisolated static func agentInstructions(vmName: String, alias: String, osDescription: String, user: String?,
                                  passwordlessSudo: Bool, shares: [SharedFolder]) -> String {
        var lines = [
            "## Sandbox VM (Cove)",
            "",
            "A disposable \(osDescription) virtual machine named “\(vmName)” is available for running code in isolation.",
            "",
            "- Run commands in it over SSH: `ssh \(alias) '<command>'` (user `\(user ?? "<user>")`, non-interactive key auth).",
            "- Copy files: `scp ./file \(alias):~/` and `scp \(alias):~/path ./`, or `rsync -az ./dir/ \(alias):~/dir/`.",
            passwordlessSudo ? "- `sudo` works without a password inside the VM." : "- `sudo` inside the VM needs the user's password — ask before using it.",
        ]
        for share in shares where share.enabled {
            lines.append("- Host folder `\(share.path)` is mounted in the VM at `/Volumes/My Shared Files/\(share.name)`\(share.readOnly ? " (read-only)" : "").")
        }
        lines += [
            "- Prefer doing risky or system-level work (installs, config changes, untrusted code) in the VM, not on the host.",
            "- The VM can be reset by restoring a snapshot in Cove — ask the user before assuming it is clean.",
        ]
        return lines.joined(separator: "\n")
    }

    // MARK: Host ~/.ssh integration

    nonisolated private static let hostSSHBookmarkKey = "hostSSHBookmark"

    /// Resolved ~/.ssh folder the user granted, if any.
    nonisolated static func hostSSHFolder() -> URL? {
        guard let data = UserDefaults.standard.data(forKey: hostSSHBookmarkKey) else { return nil }
        var stale = false
        return try? URL(resolvingBookmarkData: data, options: .withSecurityScope, bookmarkDataIsStale: &stale)
    }

    nonisolated static var isHostInstalled: Bool {
        guard let dir = hostSSHFolder() else { return false }
        let ok = dir.startAccessingSecurityScopedResource()
        defer { if ok { dir.stopAccessingSecurityScopedResource() } }
        return FileManager.default.fileExists(atPath: dir.appending(path: "cove/config").path)
    }

    /// The user picked their ~/.ssh folder (or home folder) in an open panel. Installs key + config + Include.
    static func installHostSSH(pickedFolder: URL, library: VMLibrary) throws {
        let ok = pickedFolder.startAccessingSecurityScopedResource()
        defer { if ok { pickedFolder.stopAccessingSecurityScopedResource() } }
        var sshDir = pickedFolder
        if sshDir.lastPathComponent != ".ssh" {
            sshDir = pickedFolder.appending(path: ".ssh", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: sshDir, withIntermediateDirectories: true,
                                                    attributes: [.posixPermissions: 0o700])
        }
        let bookmark = try pickedFolder.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
        UserDefaults.standard.set(bookmark, forKey: hostSSHBookmarkKey)
        try writeHostFiles(sshDir: sshDir, library: library, addInclude: true)
    }

    /// Rewrites ~/.ssh/cove/config (e.g. after an IP change). No-op when not installed.
    static func refreshHostConfig(library: VMLibrary) {
        guard let picked = hostSSHFolder() else { return }
        let ok = picked.startAccessingSecurityScopedResource()
        defer { if ok { picked.stopAccessingSecurityScopedResource() } }
        let sshDir = picked.lastPathComponent == ".ssh" ? picked : picked.appending(path: ".ssh")
        try? writeHostFiles(sshDir: sshDir, library: library, addInclude: false)
    }

    private static func writeHostFiles(sshDir: URL, library: VMLibrary, addInclude: Bool) throws {
        let fm = FileManager.default
        let coveDir = sshDir.appending(path: "cove", directoryHint: .isDirectory)
        try fm.createDirectory(at: coveDir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])

        try ensureKeyPair(in: library)
        let key = keyURL(in: library)
        for (src, name, mode) in [(key, keyName, 0o600), (key.appendingPathExtension("pub"), "\(keyName).pub", 0o644)] {
            let dst = coveDir.appending(path: name)
            try? fm.removeItem(at: dst)
            try fm.copyItem(at: src, to: dst)
            try fm.setAttributes([.posixPermissions: mode], ofItemAtPath: dst.path)
        }

        var config = "# Managed by Cove — regenerated automatically. Edit ~/.ssh/config instead.\n"
        for item in library.items where item.config.access.enabled {
            let alias = alias(for: item.name)
            let ip = item.config.macAddress.flatMap { ipAddress(forMAC: $0) }
            config += """

            Host \(alias)
              HostName \(ip ?? "\(alias).local")
              User \(guestUser(for: item) ?? NSUserName())
              IdentityFile ~/.ssh/cove/\(keyName)
              IdentitiesOnly yes
              HostKeyAlias \(alias)
              StrictHostKeyChecking accept-new
              UserKnownHostsFile ~/.ssh/cove/known_hosts
              ServerAliveInterval 30
              ConnectTimeout 5

            """
        }
        let configURL = coveDir.appending(path: "config")
        try config.write(to: configURL, atomically: true, encoding: .utf8)
        try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: configURL.path)

        guard addInclude else { return }
        // `Include` must come before any Host block, or it would only apply inside that block.
        let userConfig = sshDir.appending(path: "config")
        let include = "Include ~/.ssh/cove/config"
        let existing = (try? String(contentsOf: userConfig, encoding: .utf8)) ?? ""
        guard !existing.contains(include) else { return }
        try ("# Added by Cove (virtual machines)\n\(include)\n\n" + existing).write(to: userConfig, atomically: true, encoding: .utf8)
        try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: userConfig.path)
    }
}

/// Live SSH status for VMs with remote access on, polled every few seconds while they run.
@MainActor @Observable
final class GuestAccessMonitor {
    static let shared = GuestAccessMonitor()

    struct Status: Equatable {
        var ip: String?
        var sshReachable = false
        var guestUser: String?
        var lastChecked: Date?
    }

    private(set) var statuses: [UUID: Status] = [:]
    private(set) var hostInstalled = GuestAccess.isHostInstalled
    @ObservationIgnored private var task: Task<Void, Never>?

    func status(for id: UUID) -> Status { statuses[id] ?? Status() }

    func start(library: VMLibrary) {
        guard task == nil else { return }
        task = Task { [weak self] in
            while !Task.isCancelled {
                await self?.poll(library: library)
                try? await Task.sleep(for: .seconds(4))
            }
        }
    }

    /// Re-check right away (e.g. after setup steps).
    func refresh(library: VMLibrary) {
        hostInstalled = GuestAccess.isHostInstalled
        Task { await poll(library: library) }
    }

    private func poll(library: VMLibrary) async {
        var ipChanged = false
        for item in library.items where item.config.access.enabled {
            var s = statuses[item.id] ?? Status()
            let ip = item.state.isLive ? item.config.macAddress.flatMap { GuestAccess.ipAddress(forMAC: $0) } : nil
            if ip != s.ip, ip != nil { ipChanged = true }
            s.ip = ip
            s.guestUser = GuestAccess.guestUser(for: item)
            s.sshReachable = if let ip { await GuestAccess.isSSHReachable(ip) } else { false }
            s.lastChecked = Date()
            if statuses[item.id] != s { statuses[item.id] = s }
        }
        if ipChanged { GuestAccess.refreshHostConfig(library: library) }
    }
}

/// Thread-safe one-shot flag.
final class OnceFlag: @unchecked Sendable {
    private var done = false
    private let lock = NSLock()
    func set() -> Bool { lock.lock(); defer { lock.unlock() }; if done { return false }; done = true; return true }
}

extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
