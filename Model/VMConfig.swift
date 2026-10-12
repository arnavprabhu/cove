import Foundation

/// Persisted per-VM settings, stored as `config.json` inside the `.cove` bundle.
struct VMConfig: Codable, Equatable, Identifiable {
    var id: UUID = UUID()
    var name: String
    var cpuCount: Int
    var memoryBytes: UInt64
    var diskBytes: UInt64
    var display: DisplaySettings = .matchHost
    var network: NetworkMode = .nat
    var macAddress: String?
    var shares: [SharedFolder] = []
    var audioEnabled: Bool = true
    var createdAt: Date = Date()
    var lastUsedAt: Date?
    var osVersion: String?
    var osBuild: String?
    var notes: String = ""
    /// SSH & agent access. `nil` (older configs) means off.
    var remoteAccess: RemoteAccessSettings?

    var access: RemoteAccessSettings {
        get { remoteAccess ?? RemoteAccessSettings() }
        set { remoteAccess = newValue }
    }

    /// Hardware-affecting fields. Changing any of these invalidates a saved machine state.
    struct HardwareFingerprint: Equatable {
        var cpuCount: Int
        var memoryBytes: UInt64
        var diskBytes: UInt64
        var display: DisplaySettings
        var network: NetworkMode
        var shares: [SharedFolder]
        var audioEnabled: Bool
        /// Remote access attaches the Cove shared folder device.
        var remoteAccessEnabled: Bool
    }

    var hardwareFingerprint: HardwareFingerprint {
        .init(cpuCount: cpuCount, memoryBytes: memoryBytes, diskBytes: diskBytes, display: display,
              network: network, shares: shares, audioEnabled: audioEnabled,
              remoteAccessEnabled: access.enabled)
    }
}

struct DisplaySettings: Codable, Equatable, Hashable {
    var widthInPixels: Int
    var heightInPixels: Int
    var pixelsPerInch: Int
    /// When true, size is derived from the main screen at start time.
    var matchesHost: Bool

    static let matchHost = DisplaySettings(widthInPixels: 2560, heightInPixels: 1600, pixelsPerInch: 220, matchesHost: true)

    static let presets: [DisplaySettings] = [
        .init(widthInPixels: 1920, heightInPixels: 1200, pixelsPerInch: 220, matchesHost: false),
        .init(widthInPixels: 2560, heightInPixels: 1600, pixelsPerInch: 220, matchesHost: false),
        .init(widthInPixels: 2880, heightInPixels: 1800, pixelsPerInch: 220, matchesHost: false),
        .init(widthInPixels: 3456, heightInPixels: 2234, pixelsPerInch: 254, matchesHost: false),
    ]

    var isRetina: Bool { pixelsPerInch >= 144 }

    var label: String {
        matchesHost ? "Matches this Mac" : "\(widthInPixels) × \(heightInPixels)\(isRetina ? " Retina" : "")"
    }
}

enum NetworkMode: Codable, Equatable, Hashable {
    case nat
    /// BSD name of the host interface, e.g. "en0". Requires com.apple.vm.networking.
    case bridged(interface: String)
    case none

    var label: String {
        switch self {
        case .nat: "Shared (NAT)"
        case .bridged(let i): "Bridged · \(i)"
        case .none: "Disconnected"
        }
    }

    static var bridgedAvailable: Bool {
        #if COVE_BRIDGED
        true
        #else
        false
        #endif
    }
}

struct SharedFolder: Codable, Equatable, Hashable, Identifiable {
    var id: UUID = UUID()
    /// Name shown inside the guest under /Volumes/My Shared Files/<name>.
    var name: String
    /// Last-known path, for display only.
    var path: String
    /// App-scoped security bookmark so the sandboxed app can reopen the folder.
    var bookmark: Data
    var readOnly: Bool = false
    var enabled: Bool = true
}

/// SSH & agent access for a VM (see Engine/GuestAccess.swift).
struct RemoteAccessSettings: Codable, Equatable, Hashable {
    /// Attach the "Cove" shared folder (setup script + public key) and track the VM's SSH status.
    var enabled = false
    /// The setup script adds a sudoers rule so agents can run `sudo` without a password.
    var passwordlessSudo = false
}
