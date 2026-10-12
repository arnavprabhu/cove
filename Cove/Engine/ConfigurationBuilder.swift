import AppKit
import Virtualization

/// Turns a bundle + `VMConfig` into a validated `VZVirtualMachineConfiguration`.
enum ConfigurationBuilder {
    struct Result {
        var configuration: VZVirtualMachineConfiguration
        /// Security-scoped URLs that must stay accessed while the VM runs; call `stopAccessing` after it stops.
        var accessedURLs: [URL]

        func stopAccessing() { accessedURLs.forEach { $0.stopAccessingSecurityScopedResource() } }
    }

    static func build(bundle: VMBundle, config: VMConfig) throws -> Result {
        let c = VZVirtualMachineConfiguration()

        let platform = VZMacPlatformConfiguration()
        platform.hardwareModel = try bundle.hardwareModel()
        platform.machineIdentifier = try bundle.machineIdentifier()
        platform.auxiliaryStorage = bundle.auxiliaryStorage()
        c.platform = platform
        c.bootLoader = VZMacOSBootLoader()

        c.cpuCount = min(max(config.cpuCount, VZVirtualMachineConfiguration.minimumAllowedCPUCount),
                         VZVirtualMachineConfiguration.maximumAllowedCPUCount)
        c.memorySize = min(max(config.memoryBytes, VZVirtualMachineConfiguration.minimumAllowedMemorySize),
                           VZVirtualMachineConfiguration.maximumAllowedMemorySize)

        let disk = try VZDiskImageStorageDeviceAttachment(url: bundle.diskURL, readOnly: false,
                                                          cachingMode: .automatic, synchronizationMode: .full)
        c.storageDevices = [VZVirtioBlockDeviceConfiguration(attachment: disk)]

        c.networkDevices = try networkDevices(for: config)

        let graphics = VZMacGraphicsDeviceConfiguration()
        graphics.displays = [displayConfiguration(for: config.display)]
        c.graphicsDevices = [graphics]

        c.keyboards = [VZMacKeyboardConfiguration()]
        c.pointingDevices = [VZMacTrackpadConfiguration(), VZUSBScreenCoordinatePointingDeviceConfiguration()]

        if config.audioEnabled {
            let sound = VZVirtioSoundDeviceConfiguration()
            let output = VZVirtioSoundDeviceOutputStreamConfiguration()
            output.sink = VZHostAudioOutputStreamSink()
            sound.streams = [output]
            c.audioDevices = [sound]
        }

        var accessed: [URL] = []
        if let fs = sharedFolders(config.shares, accessed: &accessed) {
            c.directorySharingDevices = [fs]
        }

        c.memoryBalloonDevices = [VZVirtioTraditionalMemoryBalloonDeviceConfiguration()]
        c.entropyDevices = [VZVirtioEntropyDeviceConfiguration()]

        do {
            try c.validate()
            try c.validateSaveRestoreSupport()
        } catch {
            accessed.forEach { $0.stopAccessingSecurityScopedResource() }
            throw error
        }
        return Result(configuration: c, accessedURLs: accessed)
    }

    static func displayConfiguration(for display: DisplaySettings) -> VZMacGraphicsDisplayConfiguration {
        if display.matchesHost, let screen = NSScreen.main {
            return VZMacGraphicsDisplayConfiguration(for: screen, sizeInPoints: screen.frame.size)
        }
        return VZMacGraphicsDisplayConfiguration(widthInPixels: display.widthInPixels,
                                                 heightInPixels: display.heightInPixels,
                                                 pixelsPerInch: display.pixelsPerInch)
    }

    private static func networkDevices(for config: VMConfig) throws -> [VZNetworkDeviceConfiguration] {
        let attachment: VZNetworkDeviceAttachment
        switch config.network {
        case .none:
            return []
        case .nat:
            attachment = VZNATNetworkDeviceAttachment()
        case .bridged(let name):
            guard NetworkMode.bridgedAvailable,
                  let iface = VZBridgedNetworkInterface.networkInterfaces.first(where: { $0.identifier == name }) else {
                attachment = VZNATNetworkDeviceAttachment()
                break
            }
            attachment = VZBridgedNetworkDeviceAttachment(interface: iface)
        }
        let net = VZVirtioNetworkDeviceConfiguration()
        net.attachment = attachment
        if let mac = config.macAddress.flatMap(VZMACAddress.init(string:)) { net.macAddress = mac }
        return [net]
    }

    private static func sharedFolders(_ shares: [SharedFolder], accessed: inout [URL]) -> VZVirtioFileSystemDeviceConfiguration? {
        var dirs: [String: VZSharedDirectory] = [:]
        for share in shares where share.enabled {
            var stale = false
            guard let url = try? URL(resolvingBookmarkData: share.bookmark, options: .withSecurityScope,
                                     bookmarkDataIsStale: &stale) else { continue }
            if url.startAccessingSecurityScopedResource() { accessed.append(url) }
            dirs[uniqueKey(share.name, in: dirs)] = VZSharedDirectory(url: url, readOnly: share.readOnly)
        }
        guard !dirs.isEmpty else { return nil }
        let fs = VZVirtioFileSystemDeviceConfiguration(tag: VZVirtioFileSystemDeviceConfiguration.macOSGuestAutomountTag)
        fs.share = VZMultipleDirectoryShare(directories: dirs)
        return fs
    }

    private static func uniqueKey(_ base: String, in dict: [String: VZSharedDirectory]) -> String {
        let clean = base.replacingOccurrences(of: "/", with: "-")
        var key = clean.isEmpty ? "Shared" : clean
        var n = 2
        while dict[key] != nil { key = "\(clean) \(n)"; n += 1 }
        return key
    }

    /// Security-scoped bookmark for a user-picked folder.
    static func makeShare(for url: URL, readOnly: Bool = false) throws -> SharedFolder {
        let data = try url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
        return SharedFolder(name: url.lastPathComponent, path: url.path, bookmark: data, readOnly: readOnly)
    }
}
