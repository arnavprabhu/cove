import AppKit
import Virtualization

/// A `.cove` document package. See §4 of the handoff for layout.
struct VMBundle: Hashable {
    static let pathExtension = "cove"

    let url: URL

    var configURL: URL { url.appending(path: "config.json") }
    var hardwareModelURL: URL { url.appending(path: "HardwareModel") }
    var machineIdentifierURL: URL { url.appending(path: "MachineIdentifier") }
    var auxiliaryStorageURL: URL { url.appending(path: "AuxiliaryStorage") }
    var diskURL: URL { url.appending(path: "Disk.img") }
    var saveStateURL: URL { url.appending(path: "SaveState.vzvmsave") }
    var snapshotsURL: URL { url.appending(path: "Snapshots", directoryHint: .isDirectory) }
    var thumbnailURL: URL { url.appending(path: "Thumbnail.png") }

    var hasSaveState: Bool { FileManager.default.fileExists(atPath: saveStateURL.path) }

    // MARK: Config

    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    func readConfig() throws -> VMConfig {
        try Self.decoder.decode(VMConfig.self, from: Data(contentsOf: configURL))
    }

    func writeConfig(_ config: VMConfig) throws {
        try Self.encoder.encode(config).write(to: configURL, options: .atomic)
    }

    // MARK: Platform identity

    func hardwareModel() throws -> VZMacHardwareModel {
        guard let model = VZMacHardwareModel(dataRepresentation: try Data(contentsOf: hardwareModelURL)) else {
            throw CoveError.corruptBundle("HardwareModel")
        }
        guard model.isSupported else { throw CoveError.hardwareModelUnsupported }
        return model
    }

    func machineIdentifier() throws -> VZMacMachineIdentifier {
        guard let id = VZMacMachineIdentifier(dataRepresentation: try Data(contentsOf: machineIdentifierURL)) else {
            throw CoveError.corruptBundle("MachineIdentifier")
        }
        return id
    }

    func auxiliaryStorage() -> VZMacAuxiliaryStorage {
        VZMacAuxiliaryStorage(url: auxiliaryStorageURL)
    }

    /// Gives the VM a new identity (used by Clone and Advanced ▸ Regenerate). Invalidates saved state.
    func regenerateMachineIdentifier() throws {
        try VZMacMachineIdentifier().dataRepresentation.write(to: machineIdentifierURL, options: .atomic)
        try? FileManager.default.removeItem(at: saveStateURL)
    }

    // MARK: Creation

    /// Creates the package, platform files and a sparse disk. Removes the package on failure.
    static func create(at url: URL, config: VMConfig, hardwareModel: VZMacHardwareModel) throws -> VMBundle {
        let fm = FileManager.default
        guard !fm.fileExists(atPath: url.path) else { throw CoveError.alreadyExists(url.lastPathComponent) }
        try fm.createDirectory(at: url, withIntermediateDirectories: true)
        let bundle = VMBundle(url: url)
        do {
            try fm.createDirectory(at: bundle.snapshotsURL, withIntermediateDirectories: true)
            try hardwareModel.dataRepresentation.write(to: bundle.hardwareModelURL)
            try VZMacMachineIdentifier().dataRepresentation.write(to: bundle.machineIdentifierURL)
            _ = try VZMacAuxiliaryStorage(creatingStorageAt: bundle.auxiliaryStorageURL,
                                          hardwareModel: hardwareModel, options: [])
            try bundle.createSparseDisk(size: config.diskBytes)
            try bundle.writeConfig(config)
        } catch {
            try? fm.removeItem(at: url)
            throw error
        }
        return bundle
    }

    func createSparseDisk(size: UInt64) throws {
        guard FileManager.default.createFile(atPath: diskURL.path, contents: nil) else {
            throw CoveError.io("Couldn’t create the virtual disk.")
        }
        try resizeDisk(to: size)
    }

    /// Grows the raw disk image (sparse). Shrinking is refused — it would corrupt the guest file system.
    func resizeDisk(to size: UInt64) throws {
        let current = (try? FileManager.default.attributesOfItem(atPath: diskURL.path)[.size] as? UInt64) ?? 0
        guard size >= current else { throw CoveError.cannotShrinkDisk }
        let fd = open(diskURL.path, O_RDWR)
        guard fd >= 0 else { throw CoveError.io("Couldn’t open the virtual disk.") }
        defer { close(fd) }
        guard ftruncate(fd, off_t(size)) == 0 else { throw CoveError.io(String(cString: strerror(errno))) }
    }

    // MARK: Disk usage

    /// Logical size of the virtual disk (what the guest sees).
    var diskCapacity: UInt64 {
        (try? diskURL.resourceValues(forKeys: [.fileSizeKey]).fileSize).map { UInt64($0) } ?? 0
    }

    /// Bytes actually allocated on the host for the virtual disk.
    var diskAllocated: UInt64 {
        (try? diskURL.resourceValues(forKeys: [.totalFileAllocatedSizeKey]).totalFileAllocatedSize).map { UInt64($0) } ?? 0
    }

    /// Bytes allocated by the whole package, including snapshots (clones count once per file, so this overestimates).
    var totalAllocated: UInt64 { FileClone.allocatedSize(of: url) }

    // MARK: Thumbnail

    func loadThumbnail() -> NSImage? { NSImage(contentsOf: thumbnailURL) }

    func writeThumbnail(_ image: NSImage) {
        guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { return }
        try? png.write(to: thumbnailURL, options: .atomic)
    }
}
