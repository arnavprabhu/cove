import Foundation

/// What a VM is for. Chosen when creating a VM; sets sensible defaults (resources, SSH access, snapshots).
/// Case order is display order (Welcome tiles, New VM picker); `.everyday` stays the default selection.
enum VMPurpose: String, Codable, CaseIterable, Identifiable {
    /// A Mac of its own for AI agents and assistants, reached over SSH.
    case agentSandbox
    /// A spare Mac for trying apps, betas and settings without touching your own.
    case everyday
    /// Clean macOS for builds, installers and OS-version testing.
    case development

    var id: String { rawValue }

    var title: String {
        switch self {
        case .everyday: "Everyday & tinkering"
        case .development: "Development & testing"
        case .agentSandbox: "Agent sandbox"
        }
    }

    var shortTitle: String {
        switch self {
        case .everyday: "Everyday"
        case .development: "Development"
        case .agentSandbox: "Agent Sandbox"
        }
    }

    var summary: String {
        switch self {
        case .everyday: "Try apps, betas and downloads. Snapshot first, roll back anytime."
        case .development: "A clean Mac for builds, installers and testing other macOS versions."
        case .agentSandbox: "A Mac of its own for AI agents and assistants, reached over SSH."
        }
    }

    var systemImage: String {
        switch self {
        case .everyday: "macwindow"
        case .development: "hammer"
        case .agentSandbox: "terminal"
        }
    }

    /// Default name for a new VM of this kind.
    var defaultName: String {
        switch self {
        case .everyday: "macOS"
        case .development: "Dev Mac"
        case .agentSandbox: "Agent Sandbox"
        }
    }

    var defaultDisk: UInt64 {
        switch self {
        case .everyday, .agentSandbox: Bytes.gb(80)
        case .development: Bytes.gb(128)
        }
    }

    /// Agent sandboxes come with SSH access and passwordless sudo (agents can't type passwords).
    var defaultRemoteAccess: RemoteAccessSettings {
        switch self {
        case .agentSandbox: RemoteAccessSettings(enabled: true, passwordlessSudo: true)
        default: RemoteAccessSettings()
        }
    }
}
