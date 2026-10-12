import Foundation

/// APFS-clone snapshots stored in `<bundle>/Snapshots/<uuid>/`.
@MainActor
enum SnapshotStore {
    private static func dir(_ bundle: VMBundle, _ id: UUID) -> URL {
        bundle.snapshotsURL.appending(path: id.uuidString, directoryHint: .isDirectory)
    }

    static func list(in bundle: VMBundle) -> [Snapshot] {
        let dirs = (try? FileManager.default.contentsOfDirectory(at: bundle.snapshotsURL, includingPropertiesForKeys: nil)) ?? []
        return dirs.compactMap { d in
            (try? Data(contentsOf: d.appending(path: "meta.json"))).flatMap { try? VMBundle.decoder.decode(Snapshot.self, from: $0) }
        }.sorted { $0.createdAt > $1.createdAt }
    }

    /// Takes a snapshot. Running VMs are paused and their memory saved ("+ memory"); stopped VMs snapshot disk only;
    /// suspended VMs include their existing saved state.
    @discardableResult
    static func take(_ item: VMItem, name: String, automatic: Bool = false) async throws -> Snapshot {
        let bundle = item.bundle
        var snap = Snapshot(name: name, includesMemory: false, automatic: automatic, osVersion: item.config.osVersion)
        let d = dir(bundle, snap.id)
        let fm = FileManager.default
        try fm.createDirectory(at: d, withIntermediateDirectories: true)
        let target = VMBundle(url: d)
        do {
            let copyFiles = {
                try FileClone.clone(bundle.diskURL, to: target.diskURL)
                try FileClone.clone(bundle.auxiliaryStorageURL, to: target.auxiliaryStorageURL)
                try FileClone.clone(bundle.configURL, to: target.configURL)
            }
            if let session = item.session, session.state.isLive {
                try await session.withPausedState(saveTo: target.saveStateURL, copyFiles)
                snap.includesMemory = true
            } else {
                try copyFiles()
                if bundle.hasSaveState {
                    try FileClone.clone(bundle.saveStateURL, to: target.saveStateURL)
                    snap.includesMemory = true
                }
            }
            try? FileClone.clone(bundle.thumbnailURL, to: target.thumbnailURL)
            try VMBundle.encoder.encode(snap).write(to: d.appending(path: "meta.json"))
        } catch {
            try? fm.removeItem(at: d)
            throw error
        }
        item.reloadSnapshots()
        return snap
    }

    /// Restores disk (+ memory if present). Automatically snapshots the current state first so it isn't lost.
    static func restore(_ item: VMItem, to snapshot: Snapshot, library: VMLibrary) async throws {
        guard item.session == nil else { throw CoveError.vmIsRunning }
        try await take(item, name: "Before restoring “\(snapshot.name)”", automatic: true)
        let bundle = item.bundle
        let src = VMBundle(url: dir(bundle, snapshot.id))
        try FileClone.clone(src.diskURL, to: bundle.diskURL)
        try FileClone.clone(src.auxiliaryStorageURL, to: bundle.auxiliaryStorageURL)
        try? FileManager.default.removeItem(at: bundle.saveStateURL)
        if snapshot.includesMemory, FileManager.default.fileExists(atPath: src.saveStateURL.path) {
            try FileClone.clone(src.saveStateURL, to: bundle.saveStateURL)
            // Saved state only restores with the exact hardware it was taken with.
            if let snapConfig = try? src.readConfig() {
                var cfg = item.config
                cfg.cpuCount = snapConfig.cpuCount
                cfg.memoryBytes = snapConfig.memoryBytes
                cfg.display = snapConfig.display
                cfg.network = snapConfig.network
                cfg.shares = snapConfig.shares
                cfg.audioEnabled = snapConfig.audioEnabled
                cfg.macAddress = snapConfig.macAddress
                try bundle.writeConfig(cfg)
                item.config = cfg
            }
        }
        try? FileClone.clone(src.thumbnailURL, to: bundle.thumbnailURL)
        item.refresh()
    }

    static func delete(_ snapshot: Snapshot, of item: VMItem) throws {
        try FileManager.default.removeItem(at: dir(item.bundle, snapshot.id))
        item.reloadSnapshots()
    }

    static func rename(_ snapshot: Snapshot, of item: VMItem, to name: String) throws {
        var s = snapshot
        s.name = name
        try VMBundle.encoder.encode(s).write(to: dir(item.bundle, s.id).appending(path: "meta.json"))
        item.reloadSnapshots()
    }

    @discardableResult
    static func cloneToNewVM(_ snapshot: Snapshot, of item: VMItem, name: String, library: VMLibrary) throws -> VMItem {
        let src = VMBundle(url: dir(item.bundle, snapshot.id))
        return try library.makeVM(named: library.uniqueName(name), from: item.config, disk: src.diskURL,
                                  auxiliary: src.auxiliaryStorageURL, hardwareModel: item.bundle.hardwareModelURL)
    }

    static func thumbnailURL(_ snapshot: Snapshot, of item: VMItem) -> URL {
        VMBundle(url: dir(item.bundle, snapshot.id)).thumbnailURL
    }
}
