import AppKit
import Virtualization

/// One VM in the library: persisted config + optional live session.
@MainActor @Observable
final class VMItem: Identifiable {
    let id: UUID
    private(set) var bundle: VMBundle
    var config: VMConfig
    var session: VMSession?
    /// Set while a VMInstallJob is building this VM.
    var installJob: VMInstallJob?
    private(set) var snapshots: [Snapshot] = []
    var thumbnail: NSImage?
    private(set) var hasSaveState: Bool

    init(bundle: VMBundle, config: VMConfig) {
        id = config.id
        self.bundle = bundle
        self.config = config
        hasSaveState = bundle.hasSaveState
        thumbnail = bundle.loadThumbnail()
        reloadSnapshots()
    }

    var name: String { config.name }

    var state: VMState {
        if let session { return session.state }
        if installJob != nil { return .installing }
        return hasSaveState ? .suspended : .stopped
    }

    var osDescription: String {
        guard let v = config.osVersion else { return "macOS" }
        return MacOSNames.describe(version: v)
    }

    func refresh() {
        hasSaveState = bundle.hasSaveState
        thumbnail = bundle.loadThumbnail()
        reloadSnapshots()
    }

    func reloadSnapshots() { snapshots = SnapshotStore.list(in: bundle) }

    fileprivate func move(to newBundle: VMBundle) { bundle = newBundle }
}

/// Owns the library folder, the VM list, and the concurrency limit.
@MainActor @Observable
final class VMLibrary {
    static let shared = VMLibrary()
    /// macOS licensing / Virtualization.framework: at most two macOS guests at once.
    static let maxRunningMacOSGuests = 2

    private(set) var rootURL: URL
    private(set) var items: [VMItem] = []
    private(set) var installJobs: [VMInstallJob] = []
    /// Bumped whenever files in the library change, so disk-derived lists (restore images) re-render.
    private(set) var storageRevision = 0
    /// Bytes allocated by the library folder; recomputed off the main thread after changes.
    private(set) var totalAllocated: UInt64 = 0

    var vmsURL: URL { rootURL.appending(path: "VMs", directoryHint: .isDirectory) }
    var restoreImagesURL: URL { rootURL.appending(path: "RestoreImages", directoryHint: .isDirectory) }

    init(rootURL: URL? = nil) {
        self.rootURL = rootURL ?? Self.resolveLibraryRoot()
        ensureFolders()
        reload()
    }

    static var defaultRootURL: URL {
        URL.applicationSupportDirectory.appending(path: "Cove", directoryHint: .isDirectory)
    }

    private static func resolveLibraryRoot() -> URL {
        if let data = UserDefaults.standard.data(forKey: Pref.libraryBookmark) {
            var stale = false
            if let url = try? URL(resolvingBookmarkData: data, options: .withSecurityScope, bookmarkDataIsStale: &stale),
               url.startAccessingSecurityScopedResource() {
                return url
            }
        }
        return defaultRootURL
    }

    private func ensureFolders() {
        let fm = FileManager.default
        try? fm.createDirectory(at: vmsURL, withIntermediateDirectories: true)
        try? fm.createDirectory(at: restoreImagesURL, withIntermediateDirectories: true)
    }

    func reload() {
        let urls = (try? FileManager.default.contentsOfDirectory(at: vmsURL, includingPropertiesForKeys: nil)) ?? []
        var next: [VMItem] = []
        for url in urls where url.pathExtension == VMBundle.pathExtension {
            let bundle = VMBundle(url: url)
            guard let config = try? bundle.readConfig() else { continue }
            if let existing = items.first(where: { $0.id == config.id }) {
                existing.refresh()
                next.append(existing)
            } else {
                next.append(VMItem(bundle: bundle, config: config))
            }
        }
        // Keep VMs that are still being installed (their bundle may not exist yet).
        for item in items where item.installJob != nil && !next.contains(where: { $0.id == item.id }) {
            next.append(item)
        }
        items = next.sorted { ($0.config.lastUsedAt ?? $0.config.createdAt) > ($1.config.lastUsedAt ?? $1.config.createdAt) }
        noteStorageChanged()
    }

    /// Call after anything adds or removes files in the library.
    func noteStorageChanged() {
        storageRevision += 1
        let root = rootURL
        Task.detached(priority: .utility) {
            let bytes = FileClone.allocatedSize(of: root)
            await MainActor.run { [weak self] in self?.totalAllocated = bytes }
        }
    }

    func item(id: UUID) -> VMItem? { items.first { $0.id == id } }

    // MARK: Running

    var liveItems: [VMItem] { items.filter { $0.state.isLive } }

    var canStartAnother: Bool { liveItems.count < Self.maxRunningMacOSGuests }

    /// Starts (or resumes from suspend) a VM. Throws `CoveError.licenseLimit` if two are already running.
    func start(_ item: VMItem, recovery: Bool = false) async throws {
        try checkStartSpace()
        if let session = item.session, session.state.isLive {
            if session.state == .paused { try await session.resume() }
            return
        }
        guard canStartAnother else { throw CoveError.licenseLimit }
        guard item.installJob == nil else { throw CoveError.vmIsRunning }
        if let mac = item.config.macAddress, VZMACAddress(string: mac) != nil {} else {
            item.config.macAddress = VZMACAddress.randomLocallyAdministered().string
        }
        item.config.lastUsedAt = Date()
        try item.bundle.writeConfig(item.config)
        let session = try VMSession(bundle: item.bundle, config: item.config)
        session.onStop = { [weak self, weak item] _ in
            guard let item else { return }
            item.session = nil
            item.refresh()
            self?.noteStorageChanged()
        }
        item.session = session
        do {
            try await session.start(recovery: recovery)
        } catch {
            item.session = nil
            item.refresh()
            throw error
        }
    }

    func restart(_ item: VMItem) async throws {
        try checkStartSpace()
        if let session = item.session { try await session.forceStop() }
        try await start(item)
    }

    private func checkStartSpace() throws {
        let available = freeSpace
        guard available >= HostInfo.minimumVMStartFreeSpace else {
            throw CoveError.notEnoughDiskSpace(needed: HostInfo.minimumVMStartFreeSpace, available: available)
        }
    }

    /// Suspends every running VM (used on quit when the "suspend on quit" preference is on).
    func suspendAll() async {
        for item in liveItems { try? await item.session?.suspend() }
    }

    // MARK: Editing

    /// Saves settings. Hardware changes discard any saved machine state (it would no longer restore).
    func update(_ item: VMItem, config newConfig: VMConfig) throws {
        let hardwareChanged = newConfig.hardwareFingerprint != item.config.hardwareFingerprint
        if newConfig.diskBytes > item.bundle.diskCapacity {
            guard item.session == nil else { throw CoveError.vmIsRunning }
            try item.bundle.resizeDisk(to: newConfig.diskBytes)
        }
        var cfg = newConfig
        if cfg.name != item.config.name {
            cfg.name = cfg.name.trimmingCharacters(in: .whitespacesAndNewlines)
            try rename(item, to: cfg.name)
        }
        try item.bundle.writeConfig(cfg)
        item.config = cfg
        if hardwareChanged, item.session == nil, item.bundle.hasSaveState {
            try? FileManager.default.removeItem(at: item.bundle.saveStateURL)
        }
        item.refresh()
    }

    private func rename(_ item: VMItem, to name: String) throws {
        guard !name.isEmpty else { return }
        let dest = vmsURL.appending(path: "\(sanitize(name)).\(VMBundle.pathExtension)")
        guard dest != item.bundle.url else { return }
        guard item.session == nil else { throw CoveError.vmIsRunning }
        guard !FileManager.default.fileExists(atPath: dest.path) else { throw CoveError.alreadyExists(name) }
        try FileManager.default.moveItem(at: item.bundle.url, to: dest)
        item.move(to: VMBundle(url: dest))
    }

    /// Moves the VM package to the Trash.
    func delete(_ item: VMItem) throws {
        guard item.session == nil else { throw CoveError.vmIsRunning }
        try FileManager.default.trashItem(at: item.bundle.url, resultingItemURL: nil)
        items.removeAll { $0.id == item.id }
        noteStorageChanged()
    }

    /// Clones the VM (APFS copy-on-write) with a new machine identifier and MAC address.
    @discardableResult
    func clone(_ item: VMItem, name: String? = nil) throws -> VMItem {
        guard item.session == nil else { throw CoveError.vmIsRunning }
        let newName = uniqueName(name ?? "\(item.name) Copy")
        return try makeVM(named: newName, from: item.config,
                          disk: item.bundle.diskURL, auxiliary: item.bundle.auxiliaryStorageURL,
                          hardwareModel: item.bundle.hardwareModelURL)
    }

    /// Shared by clone and "Clone snapshot to new VM".
    func makeVM(named name: String, from base: VMConfig, disk: URL, auxiliary: URL, hardwareModel: URL) throws -> VMItem {
        let dest = vmsURL.appending(path: "\(sanitize(name)).\(VMBundle.pathExtension)")
        let fm = FileManager.default
        try fm.createDirectory(at: dest, withIntermediateDirectories: false)
        let bundle = VMBundle(url: dest)
        do {
            try fm.createDirectory(at: bundle.snapshotsURL, withIntermediateDirectories: true)
            try FileClone.clone(disk, to: bundle.diskURL)
            try FileClone.clone(auxiliary, to: bundle.auxiliaryStorageURL)
            try FileClone.clone(hardwareModel, to: bundle.hardwareModelURL)
            try bundle.regenerateMachineIdentifier()
            var cfg = base
            cfg.id = UUID()
            cfg.name = name
            cfg.createdAt = Date()
            cfg.lastUsedAt = nil
            cfg.macAddress = VZMACAddress.randomLocallyAdministered().string
            try bundle.writeConfig(cfg)
            let item = VMItem(bundle: bundle, config: cfg)
            items.insert(item, at: 0)
            noteStorageChanged()
            return item
        } catch {
            try? fm.removeItem(at: dest)
            throw error
        }
    }

    /// Exports a stopped VM as a copy of its `.cove` package (without snapshots or saved state).
    func export(_ item: VMItem, to destination: URL) throws {
        guard item.session == nil else { throw CoveError.vmIsRunning }
        let fm = FileManager.default
        try fm.createDirectory(at: destination, withIntermediateDirectories: false)
        let out = VMBundle(url: destination)
        for (src, dst) in [(item.bundle.diskURL, out.diskURL), (item.bundle.auxiliaryStorageURL, out.auxiliaryStorageURL),
                           (item.bundle.hardwareModelURL, out.hardwareModelURL),
                           (item.bundle.machineIdentifierURL, out.machineIdentifierURL),
                           (item.bundle.configURL, out.configURL)] {
            try FileClone.clone(src, to: dst)
        }
        try? FileClone.clone(item.bundle.thumbnailURL, to: out.thumbnailURL)
    }

    /// Imports a `.cove` package into the library (cloned, gets a new library id if it collides).
    @discardableResult
    func importVM(from url: URL) throws -> VMItem {
        let src = VMBundle(url: url)
        var cfg = try src.readConfig()
        cfg.name = uniqueName(cfg.name)
        if item(id: cfg.id) != nil { cfg.id = UUID() }
        let dest = vmsURL.appending(path: "\(sanitize(cfg.name)).\(VMBundle.pathExtension)")
        try FileManager.default.copyItem(at: url, to: dest) // clonefile-backed on APFS
        let bundle = VMBundle(url: dest)
        try? FileManager.default.removeItem(at: bundle.saveStateURL)
        try bundle.writeConfig(cfg)
        let item = VMItem(bundle: bundle, config: cfg)
        items.insert(item, at: 0)
        return item
    }

    // MARK: Install

    @discardableResult
    func beginInstall(_ request: VMInstallJob.Request) -> VMInstallJob {
        let job = VMInstallJob(request: request, library: self)
        job.onReadyToBoot = { AppRouter.shared.openConsole($0.id) }
        installJobs.append(job)
        job.run()
        return job
    }

    func installJob(id: UUID) -> VMInstallJob? { installJobs.first { $0.id == id } }

    func removeInstallJob(_ job: VMInstallJob) { installJobs.removeAll { $0 === job } }

    /// Called by VMInstallJob once the bundle exists so the VM appears in the sidebar as "Installing".
    func registerInstalling(bundle: VMBundle, config: VMConfig, job: VMInstallJob) -> VMItem {
        let item = VMItem(bundle: bundle, config: config)
        item.installJob = job
        items.insert(item, at: 0)
        return item
    }

    func discard(_ item: VMItem) {
        try? FileManager.default.removeItem(at: item.bundle.url)
        items.removeAll { $0.id == item.id }
        noteStorageChanged()
    }

    // MARK: Storage

    var freeSpace: UInt64 { HostInfo.freeDiskSpace(at: rootURL) }

    var restoreImages: [URL] {
        _ = storageRevision
        return ((try? FileManager.default.contentsOfDirectory(at: restoreImagesURL, includingPropertiesForKeys: [.fileSizeKey])) ?? [])
            .filter { $0.pathExtension == "ipsw" }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
    }

    /// Moves a cached restore image (and any partial-download resume data) to the Trash.
    func deleteRestoreImage(_ url: URL) throws {
        try FileManager.default.trashItem(at: url, resultingItemURL: nil)
        try? FileManager.default.removeItem(at: url.appendingPathExtension("resume"))
        noteStorageChanged()
    }

    /// Moves the whole library to a user-chosen folder (all VMs must be stopped).
    func moveLibrary(to newRoot: URL) throws {
        guard liveItems.isEmpty, installJobs.allSatisfy({ $0.isFinished }) else { throw CoveError.vmIsRunning }
        let fm = FileManager.default
        let dest = newRoot.appending(path: "Cove", directoryHint: .isDirectory)
        try fm.createDirectory(at: dest, withIntermediateDirectories: true)
        for sub in ["VMs", "RestoreImages"] {
            let from = rootURL.appending(path: sub), to = dest.appending(path: sub)
            if fm.fileExists(atPath: from.path) { try fm.moveItem(at: from, to: to) }
        }
        let bookmark = try newRoot.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
        UserDefaults.standard.set(bookmark, forKey: Pref.libraryBookmark)
        rootURL = dest
        items = []
        ensureFolders()
        reload()
    }

    // MARK: Naming

    func uniqueName(_ base: String) -> String {
        let names = Set(items.map(\.name))
        guard names.contains(base) else { return base }
        var n = 2
        while names.contains("\(base) \(n)") { n += 1 }
        return "\(base) \(n)"
    }

    func sanitize(_ name: String) -> String {
        name.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
    }
}

enum MacOSNames {
    static func marketingName(major: Int) -> String? {
        switch major {
        case 12: "Monterey"
        case 13: "Ventura"
        case 14: "Sonoma"
        case 15: "Sequoia"
        case 26: "Tahoe"
        default: nil
        }
    }

    /// "15.2" → "macOS 15 Sequoia"
    static func describe(version: String) -> String {
        let major = Int(version.split(separator: ".").first ?? "") ?? 0
        if let n = marketingName(major: major) { return "macOS \(major) \(n)" }
        return "macOS \(version)"
    }

    static func versionString(_ v: OperatingSystemVersion) -> String {
        "\(v.majorVersion).\(v.minorVersion)" + (v.patchVersion > 0 ? ".\(v.patchVersion)" : "")
    }
}
