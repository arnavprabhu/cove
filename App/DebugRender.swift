#if DEBUG
import AppKit
import SwiftUI

/// Debug-only: `-coveRender <outputDir>` renders each screen against a throwaway sample library to PNGs
/// (dark and light), for visual review. No screen-recording permission needed.
@MainActor
enum DebugRender {
    static func runIfRequested() {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-coveRender"), i + 1 < args.count else { return }
        let out = URL(fileURLWithPath: args[i + 1], isDirectory: true)
        try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        Task {
            // Let the app finish launching before rendering.
            try? await Task.sleep(for: .seconds(1))
            render(to: out)
            exit(0)
        }
    }

    private static func render(to out: URL) {
        let root = FileManager.default.temporaryDirectory.appending(path: "cove-render-\(UUID().uuidString)")
        let empty = VMLibrary(rootURL: root.appending(path: "empty"))
        let sample = VMLibrary(rootURL: root.appending(path: "sample"))
        let first = makeSampleVMs(in: sample)
        let lowDisk = DiskSpaceMonitor(available: 12_000_000_000)
        let failedDownload = sample.addFailedDownloadSample()
        let downloading = sample.addDownloadingSample()
        let remote = VMLibrary(rootURL: root.appending(path: "remote"))
        let remoteID = makeSampleVMs(in: remote)
        if let item = remote.item(id: remoteID) {
            var config = item.config
            config.access.enabled = true
            config.access.passwordlessSudo = true
            try? remote.update(item, config: config)
        }
        let setup = RemoteAccessProgress(enabled: true, isLive: true, needsRestart: false,
                                         status: .init(ip: "192.168.64.6"), hostInstalled: false)
        let connected = RemoteAccessProgress(enabled: true, isLive: true, needsRestart: false,
                                             status: .init(ip: "192.168.64.6", sshReachable: true, guestUser: "arnav"),
                                             hostInstalled: false)
        var ready = connected
        ready.hostInstalled = true
        var restart = setup
        restart.needsRestart = true
        let off = RemoteAccessProgress(enabled: false, isLive: false, needsRestart: false,
                                       status: .init(), hostInstalled: false)
        var stopped = setup
        stopped.isLive = false
        stopped.status = .init()

        let screens: [(String, CGSize, VMLibrary, AnyView)] = [
            ("01-Welcome", CGSize(width: 1200, height: 760), empty, AnyView(WelcomeView())),
            ("02-NewVM", CGSize(width: 1000, height: 720), sample, AnyView(NewVMView())),
            ("02b-NewVM-agent-short", CGSize(width: 900, height: 560), sample, AnyView(NewVMView(initialPurpose: .agentSandbox))),
            ("05-Library", CGSize(width: 1200, height: 760), sample, AnyView(LibraryView())),
            ("06-Console-stopped", CGSize(width: 1200, height: 760), sample, AnyView(VMWindow(vmID: first))),
            ("07-Snapshots", CGSize(width: 1200, height: 760), sample, AnyView(SnapshotsView(vmID: first))),
            ("08-MenuBar", CGSize(width: 360, height: 520), sample, AnyView(MenuBarView())),
            ("09-VMSettings", CGSize(width: 760, height: 600), sample, AnyView(VMSettingsView(vmID: first))),
            ("10-AppSettings", CGSize(width: 780, height: 540), sample, AnyView(AppSettingsView())),
            ("11-Unsupported", CGSize(width: 900, height: 600), sample, AnyView(UnsupportedMacView())),
            ("12-LicenseLimit", CGSize(width: 430, height: 360), sample,
             AnyView(LicenseLimitView(targetName: "Clean Sonoma", runningItems: [
                .init(id: UUID(), name: "Sequoia QA", canSuspend: true),
                .init(id: UUID(), name: "Tahoe Dev", canSuspend: true)
             ], onCancel: {}, onStart: { _ in }).frame(maxWidth: .infinity, maxHeight: .infinity).background(Theme.windowBackground))),
            ("13-Library-lowdisk", CGSize(width: 1200, height: 760), sample, AnyView(LibraryView(diskSpace: lowDisk))),
            ("14-NewVM-lowdisk", CGSize(width: 1000, height: 680), sample, AnyView(NewVMView(diskSpace: lowDisk))),
            ("15b-Install-downloading", CGSize(width: 1200, height: 760), sample,
             AnyView(InstallProgressView(jobID: downloading.id))),
            ("15-Install-downloadFailed", CGSize(width: 1000, height: 680), sample,
             AnyView(InstallProgressView(jobID: failedDownload.id, diskSpace: lowDisk))),
            ("16-Remote-off", CGSize(width: 760, height: 640), sample,
             AnyView(RemoteAccessView(vmID: first, sampleProgress: off))),
            ("17-Remote-start", CGSize(width: 760, height: 640), remote,
             AnyView(RemoteAccessView(vmID: remoteID, sampleProgress: stopped))),
            ("18-Remote-restart", CGSize(width: 760, height: 640), remote,
             AnyView(RemoteAccessView(vmID: remoteID, sampleProgress: restart))),
            ("19-Remote-setup", CGSize(width: 760, height: 760), remote,
             AnyView(RemoteAccessView(vmID: remoteID, sampleProgress: setup))),
            ("20-Remote-connect", CGSize(width: 760, height: 820), remote,
             AnyView(RemoteAccessView(vmID: remoteID, sampleProgress: connected, expandedStep: 4))),
            ("21-Remote-host", CGSize(width: 760, height: 960), remote,
             AnyView(RemoteAccessView(vmID: remoteID, sampleProgress: connected))),
            ("22-Remote-ready", CGSize(width: 760, height: 900), remote,
             AnyView(RemoteAccessView(vmID: remoteID, sampleProgress: ready))),
            ("23-VMSettings-network", CGSize(width: 760, height: 600), remote,
             AnyView(VMSettingsView.networkSample(vmID: remoteID))),
            ("24-Remote-window", CGSize(width: 760, height: 640), remote,
             AnyView(RemoteAccessView(vmID: remoteID, sampleProgress: ready))),
        ]
        for (name, size, library, view) in screens {
            for (suffix, appearance) in [("dark", NSAppearance.Name.darkAqua), ("light", .aqua)] {
                let url = out.appending(path: "\(name)-\(suffix).png")
                snapshot(view.environment(library), size: size, appearance: appearance, to: url)
                print("[cove-render] \(url.path)")
            }
        }
        try? FileManager.default.removeItem(at: root)
        if let icon = NSApp.applicationIconImage, let tiff = icon.tiffRepresentation,
           let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
            try? png.write(to: out.appending(path: "00-AppIcon.png"))
        }
    }

    private static func snapshot(_ view: some View, size: CGSize, appearance: NSAppearance.Name, to url: URL) {
        let host = NSHostingView(rootView: view.frame(width: size.width, height: size.height))
        host.frame = CGRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: appearance)
        window.contentView = host
        window.orderBack(nil)
        window.alphaValue = 0.01
        // Let SwiftUI lay out and run onAppear.
        for _ in 0..<5 { RunLoop.main.run(until: Date().addingTimeInterval(0.15)) }
        host.layoutSubtreeIfNeeded()
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
        host.cacheDisplay(in: host.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
        window.orderOut(nil)
    }

    /// Mirrors the Library mockup: Tahoe Dev, Sequoia QA (suspended), Clean Sonoma.
    private static func makeSampleVMs(in library: VMLibrary) -> UUID {
        let specs: [(String, String, Int, Int, Int, Bool, [String], TimeInterval)] = [
            ("Tahoe Dev", "26.0", 4, 8, 80, false, ["Fresh install", "Xcode installed", "Before beta 3"], -2_700),
            ("Sequoia QA", "15.2", 2, 6, 64, true, ["Clean state"], -86_400 * 2),
            ("Clean Sonoma", "14.6", 4, 8, 80, false, ["Fresh install", "Tools"], -86_400 * 21),
        ]
        var firstID = UUID()
        for (index, s) in specs.enumerated() {
            let url = library.vmsURL.appending(path: "\(s.0).cove")
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            let bundle = VMBundle(url: url)
            try? FileManager.default.createDirectory(at: bundle.snapshotsURL, withIntermediateDirectories: true)
            try? bundle.createSparseDisk(size: Bytes.gb(s.4))
            var cfg = VMConfig(name: s.0, cpuCount: s.2, memoryBytes: Bytes.gb(s.3), diskBytes: Bytes.gb(s.4),
                               macAddress: "6e:0b:4a:21:9c:0\(index)", osVersion: s.1, osBuild: "25A100")
            cfg.lastUsedAt = Date().addingTimeInterval(s.7)
            if index == 0 { firstID = cfg.id }
            try? bundle.writeConfig(cfg)
            if s.5 { FileManager.default.createFile(atPath: bundle.saveStateURL.path, contents: Data()) }
            for (n, snapName) in s.6.enumerated() {
                let snap = Snapshot(name: snapName, createdAt: Date().addingTimeInterval(-86_400 * Double(10 - n * 3)),
                                    includesMemory: n == s.6.count - 1, osVersion: s.1)
                let dir = bundle.snapshotsURL.appending(path: snap.id.uuidString)
                try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                try? VMBundle.encoder.encode(snap).write(to: dir.appending(path: "meta.json"))
            }
        }
        library.reload()
        return firstID
    }
}
#endif
