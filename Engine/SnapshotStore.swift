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
            let copyDisks = {
                try FileClone.clone(bundle.diskURL, to: target.diskURL)
                try FileClone.clone(bundle.auxiliaryStorageURL, to: target.auxiliaryStorageURL)
            }
            if let session = item.session, session.state.isLive {
                // Record the hardware the VM is really running with, so the memory restores later.
                try await session.withPausedState(saveTo: target.saveStateURL) {
                    try copyDisks()
                    try target.writeConfig(session.runningConfig)
                }
                snap.includesMemory = true
            } else {
                try copyDisks()
                if bundle.hasSaveState {
                    try FileClone.clone(bundle.saveStateURL, to: target.saveStateURL)
                    try target.writeConfig(bundle.readSaveStateConfig() ?? item.config)
                    snap.includesMemory = true
                } else {
                    try FileClone.clone(bundle.configURL, to: target.configURL)
                }
            }
            try? FileClone.clone(bundle.thumbnailURL, to: target.thumbnailURL)
            try VMBundle.encoder.encode(snap).write(to: d.appending(path: "meta.json"))
        } catch {
            try? fm.removeItem(at: d)
            throw error
        }
        item.reloadSnapshots()
        VMLibrary.shared.noteStorageChanged()
        return snap
    }

    /// Restores disk (+ memory if present). Automatically snapshots the current state first so it isn't lost.
    static func restore(_ item: VMItem, to snapshot: Snapshot, library: VMLibrary) async throws {
        guard item.session == nil else { throw CoveError.vmIsRunning }
        let bundle = item.bundle
        let src = VMBundle(url: dir(bundle, snapshot.id))
        // All-or-nothing: make sure the snapshot is complete before touching anything.
        var needed = [src.diskURL, src.auxiliaryStorageURL]
        if snapshot.includesMemory { needed.append(src.saveStateURL) }
        if let missing = needed.first(where: { !FileManager.default.fileExists(atPath: $0.path) }) {
            throw CoveError.corruptBundle("snapshot “\(snapshot.name)” is missing \(missing.lastPathComponent)")
        }
        try await take(item, name: "Before restoring “\(snapshot.name)”", automatic: true)
        try FileClone.clone(src.diskURL, to: bundle.diskURL)
        try FileClone.clone(src.auxiliaryStorageURL, to: bundle.auxiliaryStorageURL)
        bundle.removeSaveState()
        if snapshot.includesMemory, FileManager.default.fileExists(atPath: src.saveStateURL.path) {
            // Memory restores only with the exact hardware it was captured with — the snapshot's config.
            try FileClone.clone(src.saveStateURL, to: bundle.saveStateURL)
            if let snapConfig = try? src.readConfig() { try bundle.writeSaveStateConfig(snapConfig) }
        }
        try? FileClone.clone(src.thumbnailURL, to: bundle.thumbnailURL)
        item.refresh()
    }

    static func delete(_ snapshot: Snapshot, of item: VMItem) throws {
        try FileManager.default.removeItem(at: dir(item.bundle, snapshot.id))
        item.reloadSnapshots()
        VMLibrary.shared.noteStorageChanged()
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
